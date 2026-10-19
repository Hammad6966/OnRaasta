const axios = require('axios');
const Job = require('../models/Job');
const Bid = require('../models/Bid');
const presence = require('./presence.service');
const { sameId, idPattern } = require('./access.service');
const { pricing } = require('./accounting.service');
const fail = require('../utils/http-error');
const POLICY = 'weighted_rules_v1';
const unavailable = () => fail(503, 'Recommendations are unavailable. Real bids remain available; please retry.');
const client = {
  async score(input) {
    try {
      const raw = process.env.AI_SERVICE_URL;
      if (!raw || raw.length > 1024) throw new Error();
      const url = new URL(raw);
      if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) throw new Error();
      url.pathname = url.pathname.replace(/\/$/, '') + '/recommend';
      const timeout = process.env.AI_RECOMMEND_TIMEOUT_MS === undefined ? 2000 : Number(process.env.AI_RECOMMEND_TIMEOUT_MS);
      if (!Number.isInteger(timeout) || timeout < 250 || timeout > 5000) throw new Error();
      const response = await axios.post(url.href, input, { timeout, maxRedirects: 0, maxBodyLength: 262144, maxContentLength: 131072, headers: { 'Content-Type': 'application/json' } });
      return response.data;
    } catch { throw unavailable(); }
  },
};
async function snapshot(jobId, actor) {
  const job = await Job.findById(jobId);
  if (!job) throw fail(404, 'Job not found');
  if (actor.role !== 'user' || !sameId(job.userId, actor.id)) throw fail(403, 'Only job owner may request recommendations');
  if (!['pending', 'bidding'].includes(job.status) || job.acceptedBidId) throw fail(409, 'Job is no longer open for recommendations');
  if (!presence.validCoordinates(job.location)) throw fail(400, 'Saved job location is unavailable');
  const eligible = new Map((await presence.nearby(job.location.lat, job.location.lng)).map(item => [String(item.mechanic._id), item]));
  const bids = await Bid.find({ jobId: job._id, status: 'pending' }).sort({ _id: 1 }).limit(501);
  const candidates = [], observations = new Map(); let truncated = bids.length > 500;
  for (const bid of bids.slice(0, 500)) {
    const item = eligible.get(String(bid.mechanicId));
    if (!item || !presence.current(item.entry)) continue;
    let quote; try { quote = pricing(bid); } catch { continue; }
    if (!idPattern.test(String(bid._id)) || !idPattern.test(String(bid.mechanicId))) continue;
    const skills = Array.isArray(item.mechanic.skills) ? item.mechanic.skills.filter(s => typeof s === 'string' && s.trim().length && s.length <= 100) : [];
    if (skills.length > 16) continue;
    const rating = item.mechanic.rating;
    const candidate = { bidId: String(bid._id), mechanicId: String(bid.mechanicId),
      skills: [...skills].sort(), rating: typeof rating === 'number' && Number.isFinite(rating) && rating >= 0 && rating <= 5 ? rating : null,
      lat: item.entry.lat, lng: item.entry.lng, serviceRadius: item.entry.serviceRadius,
      labourMinor: quote.labourMinor, partsMinor: quote.partsMinor, totalMinor: quote.totalMinor };
    if (candidates.length === 100) { truncated = true; break; }
    candidates.push(candidate); observations.set(candidate.bidId, new Date(item.entry.updatedAt).toISOString());
  }
  const diagnosis = job.aiDiagnosis;
  const input = { job: { jobId: String(job._id), location: { lat: job.location.lat, lng: job.location.lng }, aiDiagnosis: diagnosis ? {
    fault_class: typeof diagnosis.fault_class === 'string' ? diagnosis.fault_class : 'unknown',
    ...(typeof diagnosis.skill_required === 'string' ? { skill_required: diagnosis.skill_required } : {}),
  } : null }, mechanics: candidates };
  return { input, observations, truncated, signature: JSON.stringify(input) };
}
function validated(raw, input) {
  if (raw?.policyVersion !== POLICY || !Array.isArray(raw.mechanics) || raw.mechanics.length !== input.mechanics.length) throw unavailable();
  const expected = new Map(input.mechanics.map(c => [c.bidId, c])), seen = new Set(), results = [];
  const unit = v => typeof v === 'number' && Number.isFinite(v) && v >= 0 && v <= 1;
  const close = (a, b) => typeof a === 'number' && Number.isFinite(a) && Math.abs(a - b) <= 1e-9;
  for (const row of raw.mechanics) {
    const c = expected.get(row?.bidId), parts = row?.components;
    if (!c || seen.has(c.bidId) || row.mechanicId !== c.mechanicId || row.totalMinor !== c.totalMinor || !unit(row.score) || !parts ||
        !['skillMatch', 'distanceScore', 'ratingScore', 'priceScore'].every(k => unit(parts[k])) || ![0, 0.5, 1].includes(parts.skillMatch)) throw unavailable();
    const distance = presence.haversine(input.job.location.lat, input.job.location.lng, c.lat, c.lng);
    if (!close(row.distanceKm, distance) || !close(parts.distanceScore, Math.max(0, 1 - distance / 15)) ||
        !close(parts.ratingScore, (c.rating ?? 0) / 5) || !close(parts.priceScore, Math.max(0, 1 - c.totalMinor / 5000000)) ||
        !close(row.score, 0.35 * parts.skillMatch + 0.25 * parts.distanceScore + 0.25 * parts.ratingScore + 0.15 * parts.priceScore) ||
        row.ratingMissing !== (c.rating === null) || !Array.isArray(row.matchedSkills) || row.matchedSkills.length > 16 || row.matchedSkills.some(s => !c.skills.includes(s)) ||
        (parts.skillMatch === 1 && row.matchedSkills.length === 0)) throw unavailable();
    const previous = results.at(-1);
    if (previous && (previous.score < row.score || previous.score === row.score && previous.bidId > row.bidId)) throw unavailable();
    seen.add(c.bidId);
    results.push({ bidId: c.bidId, mechanicId: c.mechanicId, score: row.score, totalMinor: c.totalMinor,
      rating: c.rating, skills: c.skills, labourMinor: c.labourMinor, partsMinor: c.partsMinor, distanceKm: row.distanceKm, ratingMissing: row.ratingMissing,
      matchedSkills: row.matchedSkills, components: { skillMatch: parts.skillMatch, distanceScore: parts.distanceScore, ratingScore: parts.ratingScore, priceScore: parts.priceScore } });
  }
  return results;
}
async function recommend(req, res, next) {
  try {
    if (Object.keys(req.query).length) throw fail(400, 'Recommendations use the saved job, not client candidates');
    const initial = await snapshot(req.params.id, req.user);
    const raw = initial.input.mechanics.length ? await client.score(initial.input) : { policyVersion: POLICY, mechanics: [] };
    const rankings = validated(raw, initial.input);
    const latest = await snapshot(req.params.id, req.user);
    if (initial.signature !== latest.signature) throw fail(409, 'Offers or availability changed; refresh recommendations');
    res.json({ success: true, data: { jobId: initial.input.job.jobId, policyVersion: POLICY, generatedAt: new Date().toISOString(),
      locationSource: 'foreground_presence', distanceType: 'straight_line_km', truncated: latest.truncated,
      expiresAt: rankings.length ? new Date(Math.min(...rankings.map(r => Date.parse(latest.observations.get(r.bidId)) + presence.LEASE_MS))).toISOString() : null,
      rankings: rankings.map(r => ({ ...r, presenceUpdatedAt: latest.observations.get(r.bidId) })) } });
  } catch (err) { next(err); }
}
module.exports = { recommend, client, snapshot, validated };
