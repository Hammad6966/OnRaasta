const mongoose = require('mongoose');
const Bid = require('../models/Bid');
const Job = require('../models/Job');
const Mechanic = require('../models/Mechanic');
const User = require('../models/User');
const { getIo, publishAssignment } = require('../socket/socket');
const { approvedMechanic, sameId, canViewJob } = require('../services/access.service');
const fail = require('../utils/http-error');
const open = ['pending', 'bidding'];

async function transaction(work) {
  const session = await mongoose.startSession();
  try { return await session.withTransaction(() => work(session)); }
  finally { await session.endSession(); }
}
const createBid = async (req, res, next) => {
  try {
    const bid = await transaction(async session => {
      const mechanic = await approvedMechanic(req.user, session);
      if (req.body.mechanicId !== undefined && !sameId(req.body.mechanicId, mechanic._id)) {
        throw fail(403, 'Cannot bid as another mechanic');
      }
      const job = await Job.findById(req.body.jobId).session(session);
      if (!job) throw fail(404, 'Job not found');
      if (!open.includes(job.status) || job.acceptedBidId) throw fail(409, 'Job is not open for bids');
      if (await Bid.exists({ jobId: job._id, mechanicId: mechanic._id, status: { $in: ['pending', 'accepted'] } }).session(session)) {
        throw fail(409, 'An active bid already exists');
      }
      // Every submission/acceptance writes the same Job: concurrent transactions conflict and retry.
      const updated = await Job.findOneAndUpdate({ _id: job._id, status: { $in: open }, acceptedBidId: null },
        { $set: { status: 'bidding' }, $inc: { __v: 1 } }, { new: true, session });
      if (!updated) throw fail(409, 'Job is not open for bids');
      const { labourCost, partsCost = 0, totalCost, eta } = req.body;
      const [created] = await Bid.create([{ jobId: job._id, mechanicId: mechanic._id,
        labourCost, partsCost, totalCost, eta, status: 'pending' }], { session });
      return created;
    });
    // Emit only committed records; socket errors never undo a successful bid.
    try {
      const mechanic = await Mechanic.findById(bid.mechanicId);
      const job = await Job.findById(bid.jobId);
      getIo()?.to(`user_${job.userId}`).emit('bid:new', {
        bidId: String(bid._id), jobId: String(bid.jobId), mechanicId: String(bid.mechanicId),
        mechanicName: req.user.name, labourCost: bid.labourCost, partsCost: bid.partsCost,
        totalCost: bid.totalCost, eta: bid.eta, status: bid.status, rating: mechanic.rating, reviewCount: mechanic.reviewCount,
        skills: mechanic.skills, isNew: true,
      });
    } catch { /* Clients can reload committed bids. */ }
    res.status(201).json({ success: true, bid });
  } catch (err) { next(err); }
};
const acceptBid = async (req, res, next) => {
  try {
    const bid = await transaction(async session => {
      const owner = await User.findOneAndUpdate({ _id: req.user.id, role: 'user', isActive: true, isVerified: true }, { $inc: { __v: 1 } }, { new: true, session });
      if (!owner) throw fail(403, 'Account is inactive or unverified');
      const current = await Bid.findById(req.params.id).session(session);
      if (!current) throw fail(404, 'Bid not found');
      const job = await Job.findById(current.jobId).session(session);
      if (!job) throw fail(404, 'Job not found');
      if (req.user.role !== 'user' || !sameId(job.userId, req.user.id)) throw fail(403, 'Only job owner may accept a bid');
      if (current.status !== 'pending' || !open.includes(job.status) || job.acceptedBidId) {
        throw fail(409, 'Bid or job is no longer open');
      }
      const mechanic = await Mechanic.findOneAndUpdate({ _id: current.mechanicId, isApproved: true },
        { $inc: { __v: 1 } }, { new: true, session });
      if (!mechanic || !await User.exists({ _id: mechanic.userId, isActive: true, isVerified: true, role: 'mechanic' }).session(session)) {
        throw fail(403, 'Mechanic is not eligible');
      }
      const assigned = await Job.findOneAndUpdate({ _id: job._id, status: { $in: open }, acceptedBidId: null },
        { $set: { status: 'accepted', mechanicId: current.mechanicId, acceptedBidId: current._id, agreedPricing: require('../services/accounting.service').pricing(current) }, $inc: { __v: 1 } },
        { new: true, session, runValidators: true });
      if (!assigned) throw fail(409, 'Another bid already won');
      await Bid.updateMany({ jobId: job._id, _id: { $ne: current._id }, status: 'pending' },
        { $set: { status: 'declined' } }, { session });
      const accepted = await Bid.findOneAndUpdate({ _id: current._id, status: 'pending' },
        { $set: { status: 'accepted' } }, { new: true, session, runValidators: true });
      if (!accepted) throw fail(409, 'Bid is no longer pending');
      return accepted;
    });
    // withTransaction has committed (including any retries) before publishing.
    // Notifications are hints; a transport/read failure must not turn a committed
    // acceptance into an apparent HTTP failure. Authenticated reads recover it.
    try { await publishAssignment(bid); } catch { /* Recover through assignment API. */ }
    res.json({ success: true, data: bid });
  } catch (err) { next(err); }
};
const getBidsByJob = async (req, res, next) => {
  try {
    const job = await Job.findById(req.query.jobId);
    if (!job) throw fail(404, 'Job not found');
    if (!await canViewJob(req.user, job)) throw fail(403, 'Job access forbidden');
    const bids = await Bid.find({ jobId: job._id }).populate({ path: 'mechanicId',
      select: 'userId skills serviceRadius shopAddress lat lng isOnline isApproved rating reviewCount totalJobs',
      populate: { path: 'userId', select: 'name phone' } });
    for (const bid of bids) if (bid.mechanicId && typeof bid.mechanicId === 'object' && bid.mechanicId._id) {
      bid.mechanicId.totalJobs = await Job.countDocuments({ mechanicId: bid.mechanicId._id, status: 'completed' });
    }
    res.json({ success: true, data: bids });
  } catch (err) { next(err); }
};
module.exports = { createBid, acceptBid, getBidsByJob };
