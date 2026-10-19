const Job = require('../models/Job');
const Mechanic = require('../models/Mechanic');
const User = require('../models/User');
const { approvedMechanic, canViewJob, sameId, idPattern, authenticateAccessToken } = require('./access.service');
const { haversine } = require('./presence.service');
const fail = require('../utils/http-error');
const FRESH_MS = 60000, RETAIN_MS = 600000, PERSIST_MS = 15000, MIN_MS = 5000;
const cache = new Map(), queues = new Map(), attempts = new Map();
async function withJobLock(id, action) {
  const prior = queues.get(id) || Promise.resolve();
  const task = prior.catch(() => {}).then(action);
  queues.set(id, task);
  try { return await task; } finally { if (queues.get(id) === task) queues.delete(id); }
}
const clearJob = id => cache.delete(String(id));
function canonical(job, point) {
  return { jobId: String(job._id), mechanicId: String(job.mechanicId), lat: point.lat, lng: point.lng,
    ...(point.accuracy !== undefined ? { accuracy: point.accuracy } : {}),
    observedAt: new Date(point.observedAt).toISOString(), receivedAt: new Date(point.receivedAt).toISOString() };
}
function usable(job, point, now) {
  return point && sameId(point.mechanicId, job.mechanicId) && sameId(point.acceptedBidId, job.acceptedBidId) &&
    now - new Date(point.receivedAt).getTime() < RETAIN_MS && new Date(point.expiresAt).getTime() > now;
}
async function publish(user, data, io, now = Date.now()) {
  // Identity/relay fields are never accepted from clients, even authenticated mechanics.
  if (user.role !== 'mechanic') throw fail(403, 'Assigned mechanic access required');
  let rate = attempts.get(user.id);
  if (!rate || now - rate.started >= 60000) {
    if (attempts.size >= 10000) attempts.delete(attempts.keys().next().value);
    rate = { started: now, count: 0 }; attempts.set(user.id, rate);
  }
  if (++rate.count > 60) throw fail(429, 'Location publishing quota exceeded; retry later');
  if (!data || typeof data !== 'object' || Array.isArray(data)) throw fail(400, 'Invalid location observation');
  if (Object.keys(data).some(k => !['jobId', 'lat', 'lng', 'accuracy', 'observedAt'].includes(k))) throw fail(403, 'Client cannot set tracking identity or relay fields');
  if (typeof data.jobId !== 'string' || !idPattern.test(data.jobId) ||
      !Number.isFinite(data.lat) || !Number.isFinite(data.lng) || Math.abs(data.lat) > 90 || Math.abs(data.lng) > 180 ||
      data.lat === 0 && data.lng === 0 || data.accuracy !== undefined && (!Number.isFinite(data.accuracy) || data.accuracy < 0 || data.accuracy > 100) ||
      typeof data.observedAt !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/.test(data.observedAt)) throw fail(400, 'Invalid coordinates, accuracy or timestamp');
  const observed = Date.parse(data.observedAt);
  if (!Number.isFinite(observed) || new Date(observed).toISOString().slice(0, 19) !== data.observedAt.slice(0, 19) || now - observed > FRESH_MS || observed - now > 10000) throw fail(400, 'Location observation is stale or in the future');
  return withJobLock(data.jobId, async () => {
    const mechanic = await approvedMechanic(user);
    const job = await Job.findById(data.jobId).select('+latestMechanicLocation');
    if (!job) throw fail(404, 'Job not found');
    if (!sameId(job.mechanicId, mechanic._id)) throw fail(403, 'Assigned mechanic access required');
    if (!job.acceptedBidId || job.status !== 'en_route') throw fail(409, 'Job does not permit location sharing');
    const oldCache = cache.get(data.jobId);
    const previous = usable(job, oldCache?.point, now) ? oldCache.point : usable(job, job.latestMechanicLocation, now) ? job.latestMechanicLocation : null;
    if (previous) {
      const delta = observed - new Date(previous.observedAt).getTime();
      if (delta === 0 && data.lat === previous.lat && data.lng === previous.lng) return { accepted: false, reason: 'duplicate', location: canonical(job, previous) };
      if (delta <= 0) throw fail(409, 'Out-of-order location observation');
      if (now - new Date(previous.receivedAt).getTime() < MIN_MS) throw fail(429, 'Location publishing is too frequent');
      const distance = haversine(previous.lat, previous.lng, data.lat, data.lng) * 1000;
      if (distance > 70 * delta / 1000 + (previous.accuracy || 0) + (data.accuracy || 0) + 50) throw fail(400, 'Implausible location jump');
    }
    const point = { mechanicId: String(mechanic._id), acceptedBidId: String(job.acceptedBidId), lat: data.lat, lng: data.lng,
      ...(data.accuracy !== undefined ? { accuracy: data.accuracy } : {}), observedAt: new Date(observed), receivedAt: new Date(now), expiresAt: new Date(now + RETAIN_MS) };
    const lastPersisted = usable(job, oldCache?.point, now) ? oldCache.persistedAt : usable(job, job.latestMechanicLocation, now) ? new Date(job.latestMechanicLocation.receivedAt).getTime() : 0;
    const persisted = !lastPersisted || now - lastPersisted >= PERSIST_MS;
    if (persisted) {
      const saved = await Job.findOneAndUpdate({ _id: job._id, status: 'en_route', mechanicId: mechanic._id, acceptedBidId: job.acceptedBidId },
        { $set: { latestMechanicLocation: point } }, { new: true, runValidators: true, timestamps: false });
      if (!saved) throw fail(409, 'Job no longer permits tracking');
    }
    // Check live account and assignment again before relay, including cache-only observations.
    const current = await Job.findById(job._id);
    await approvedMechanic(user);
    if (!await User.exists({ _id: user.id, role: 'mechanic', isActive: true, isVerified: true })) throw fail(403, 'Account is inactive or unverified');
    if (!current || current.status !== 'en_route' || !sameId(current.mechanicId, mechanic._id) || !sameId(current.acceptedBidId, job.acceptedBidId)) throw fail(409, 'Job no longer permits tracking');
    if (cache.size >= 10000 && !cache.has(data.jobId)) cache.delete(cache.keys().next().value);
    cache.set(data.jobId, { point, persistedAt: persisted ? now : lastPersisted });
    const output = canonical(current, point), room = `user_${current.userId}`;
    if (io) {
      for (const socket of io.sockets.sockets.values()) {
        if (!socket.rooms.has(room)) continue;
        try {
          const owner = await authenticateAccessToken(socket.handshake.auth?.token);
          if (owner.role !== 'user' || !sameId(owner.id, current.userId)) await socket.leave(room);
        } catch { socket.disconnect(true); }
      }
      io.to(room).emit('job:mechanic_location', output);
    }
    // Receipt confirms acceptance, never that an offline driver received it.
    return { accepted: true, persisted, location: output };
  });
}
async function latest(req, res, next) {
  try {
    const job = await Job.findById(req.params.id).select('+latestMechanicLocation');
    if (!job) throw fail(404, 'Job not found');
    if (!await canViewJob(req.user, job)) throw fail(403, 'Job location access forbidden');
    const mechanic = job.mechanicId ? await Mechanic.findById(job.mechanicId) : null;
    const eligible = mechanic?.isApproved && await User.exists({ _id: mechanic.userId, role: 'mechanic', isActive: true, isVerified: true });
    const now = Date.now(), allowed = !!(job.status === 'en_route' && job.acceptedBidId && eligible);
    const cached = cache.get(String(job._id))?.point;
    const point = allowed && (usable(job, cached, now) ? cached : usable(job, job.latestMechanicLocation, now) ? job.latestMechanicLocation : null);
    const ageMs = point ? Math.max(0, now - new Date(point.observedAt).getTime()) : null;
    res.json({ success: true, data: { jobId: String(job._id), trackingAllowed: allowed,
      location: point ? canonical(job, point) : null, ageMs, fresh: point ? ageMs <= FRESH_MS : false,
      serverTime: new Date(now).toISOString(), freshForSeconds: FRESH_MS / 1000 } });
  } catch (err) { next(err); }
}
async function sweep(now = Date.now()) {
  for (const [id, value] of cache) if (new Date(value.point.expiresAt).getTime() <= now) cache.delete(id);
  for (const [id, value] of attempts) if (now - value.started >= 60000) attempts.delete(id);
  await Job.updateMany({ 'latestMechanicLocation.expiresAt': { $lte: new Date(now) } },
    { $set: { latestMechanicLocation: null } }, { timestamps: false });
}
module.exports = { publish, latest, sweep, clearJob, withJobLock, clearCache: () => { cache.clear(); attempts.clear(); } };
