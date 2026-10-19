const mongoose = require('mongoose');
const Job = require('../models/Job');
const Bid = require('../models/Bid');
const User = require('../models/User');
const Mechanic = require('../models/Mechanic');
const { sameId, idPattern } = require('./access.service');
const fail = require('../utils/http-error');
const { tags, clean } = require('../utils/review-policy');

// Only completed, assignment-backed reviews are reputation evidence. This also
// excludes malformed historical data instead of trusting old cached averages.
async function evidence(mechanicId, session) {
  const jobs = await Job.find({ mechanicId, status: 'completed', 'review.stars': { $exists: true } })
    .select('mechanicId acceptedBidId review').session(session);
  const bids = await Bid.find({ mechanicId, status: 'accepted', _id: { $in: jobs.map(j => j.acceptedBidId).filter(id => id && idPattern.test(String(id))) } })
    .select('jobId mechanicId').session(session);
  const accepted = new Map(bids.map(b => [String(b._id), b]));
  const valid = jobs.filter(j => Number.isInteger(j.review?.stars) && j.review.stars >= 1 && j.review.stars <= 5 &&
    j.review.createdAt && Number.isFinite(new Date(j.review.createdAt).getTime()) &&
    sameId(accepted.get(String(j.acceptedBidId))?.jobId, j._id));
  valid.sort((a, b) => new Date(b.review.createdAt) - new Date(a.review.createdAt) || String(b._id).localeCompare(String(a._id)));
  const distribution = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 };
  let sum = 0;
  for (const job of valid) { distribution[job.review.stars]++; sum += job.review.stars; }
  return { jobs: valid, rating: valid.length ? Math.round(sum / valid.length * 100) / 100 : 0,
    reviewCount: valid.length, distribution };
}
async function submit(req, res, next) {
  let session;
  try {
    session = await mongoose.startSession();
    const result = await session.withTransaction(async () => {
      // Write guards make account changes and submissions conflict atomically.
      const account = await User.findOneAndUpdate({ _id: req.user.id, role: 'user', isActive: true, isVerified: true },
        { $inc: { __v: 1 } }, { new: true, session });
      if (!account) throw fail(403, 'Active verified driver required');
      const job = await Job.findById(req.params.id).session(session);
      if (!job) throw fail(404, 'Job not found');
      if (!sameId(job.userId, req.user.id)) throw fail(403, 'Only job owner may review');
      if (job.status !== 'completed') throw fail(409, 'Only completed jobs may be reviewed');
      if (job.review?.stars != null) throw fail(409, 'Already reviewed');
      if (!job.mechanicId || !job.acceptedBidId) throw fail(409, 'Confirmed assignment is missing');
      const bid = await Bid.findOne({ _id: job.acceptedBidId, jobId: job._id, mechanicId: job.mechanicId, status: 'accepted' }).session(session);
      if (!bid) throw fail(409, 'Confirmed assignment is invalid');
      // All reviews of a mechanic contend on this document. Mongo transaction
      // retries get a fresh snapshot, preventing concurrent aggregate lost updates.
      const mechanic = await Mechanic.findOneAndUpdate({ _id: job.mechanicId }, { $inc: { __v: 1 } }, { new: true, session });
      if (!mechanic) throw fail(409, 'Assigned mechanic no longer exists');
      const review = { stars: req.body.stars, tags: req.body.tags ?? [], comment: clean(req.body.comment ?? ''), createdAt: new Date() };
      const saved = await Job.findOneAndUpdate({ _id: job._id, userId: req.user.id, status: 'completed',
        mechanicId: job.mechanicId, acceptedBidId: job.acceptedBidId, 'review.stars': { $exists: false } },
      { $set: { review } }, { new: true, runValidators: true, session });
      if (!saved) throw fail(409, 'Already reviewed or assignment changed');
      const stats = await evidence(job.mechanicId, session);
      await Mechanic.findOneAndUpdate({ _id: job.mechanicId },
        { $set: { rating: stats.rating, reviewCount: stats.reviewCount } }, { session, runValidators: true });
      return { jobId: String(saved._id), mechanicId: String(job.mechanicId), review: saved.review,
        reputation: { rating: stats.rating, reviewCount: stats.reviewCount, distribution: stats.distribution } };
    });
    res.json({ success: true, message: 'Review submitted', data: result });
  } catch (err) { next(err); }
  finally { if (session) await session.endSession(); }
}
async function list(req, res, next) {
  try {
    const { page = '1', limit = '10', ...extra } = req.query;
    if (Object.keys(extra).length || typeof page !== 'string' || typeof limit !== 'string' || !/^[1-9]\d{0,5}$/.test(page) || !/^[1-9]\d?$/.test(limit) || Number(limit) > 50) throw fail(400, 'Invalid review pagination');
    const mechanic = await Mechanic.findById(req.params.mechanicId).select('userId isApproved rating reviewCount');
    if (!mechanic) throw fail(404, 'Mechanic not found');
    if (!mechanic.isApproved && req.user.role !== 'admin' && !sameId(mechanic.userId, req.user.id)) throw fail(403, 'Mechanic profile is not public');
    let stats = await evidence(mechanic._id);
    // Lazy repair of pre-R08 cached ratings/counts. No bulk migration. Serialize
    // with submission so a read cannot overwrite a concurrently committed review.
    if (mechanic.rating !== stats.rating || mechanic.reviewCount !== stats.reviewCount) {
      const session = await mongoose.startSession();
      try {
        stats = await session.withTransaction(async () => {
          const filter = { _id: mechanic._id };
          if (req.user.role !== 'admin' && !sameId(mechanic.userId, req.user.id)) filter.isApproved = true;
          const current = await Mechanic.findOneAndUpdate(filter, { $inc: { __v: 1 } }, { new: true, session });
          if (!current) throw fail(403, 'Mechanic profile is no longer available');
          const fresh = await evidence(mechanic._id, session);
          await Mechanic.findOneAndUpdate({ _id: mechanic._id },
            { $set: { rating: fresh.rating, reviewCount: fresh.reviewCount } }, { session, runValidators: true });
          return fresh;
        });
      } finally { await session.endSession(); }
    }
    const offset = (Number(page) - 1) * Number(limit);
    // Anonymous, explicit allowlist: no full Job, reviewer identity or account data.
    const reviews = stats.jobs.slice(offset, offset + Number(limit)).map(j => ({ stars: j.review.stars,
      tags: Array.isArray(j.review.tags) ? j.review.tags.filter(t => tags.includes(t)) : [],
      comment: typeof j.review.comment === 'string' ? clean(j.review.comment).slice(0, 300) : '', createdAt: j.review.createdAt }));
    res.json({ success: true, data: { mechanicId: String(mechanic._id), rating: stats.rating,
      reviewCount: stats.reviewCount, distribution: stats.distribution, reviews,
      page: Number(page), limit: Number(limit), hasMore: offset + reviews.length < stats.reviewCount } });
  } catch (err) { next(err); }
}
module.exports = { submit, list, evidence, tags };
