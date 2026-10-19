const Mechanic = require('../models/Mechanic');

const presence = require('../services/presence.service');
const Job = require('../models/Job');
const { approvedMechanic, sameId } = require('../services/access.service');
const fail = require('../utils/http-error');

const getNearby = async (req, res, next) => {
  try {
    const eligible = await presence.nearby(Number(req.query.lat), Number(req.query.lng));
    const data = await Promise.all(eligible.filter(({ entry }) => presence.current(entry)).map(async ({ entry, mechanic, user, distance }) => ({
      _id: entry.mechanicId, userId: { _id: user.id, name: user.name },
      skills: mechanic.skills, serviceRadius: entry.serviceRadius, shopAddress: mechanic.shopAddress,
      lat: entry.lat, lng: entry.lng, isOnline: true, isApproved: true,
      rating: mechanic.rating, reviewCount: mechanic.reviewCount, totalJobs: await Job.countDocuments({ mechanicId: mechanic._id, status: 'completed' }), distance,
    })));
    res.json({ success: true, data: data.filter(item => presence.isOnline(item._id)) });
  } catch (err) { next(err); }
};
// Foreground reconnect recovery only: no accepted-job/assignment recovery here.
const getOpenRequests = async (req, res, next) => {
  try {
    const mechanic = await approvedMechanic(req.user);
    const active = (await presence.eligibleEntries()).find(({ entry }) => sameId(entry.mechanicId, mechanic._id));
    if (!active || !presence.current(active.entry)) throw fail(409, 'Go online before loading nearby requests');
    const jobs = await Job.find({ status: { $in: ['pending', 'bidding'] }, acceptedBidId: null }).sort({ createdAt: -1 });
    const data = jobs.filter(job => presence.validCoordinates(job.location)).map(job => ({
      jobId: String(job._id), description: job.description, location: job.location,
      aiDiagnosis: job.aiDiagnosis, createdAt: job.createdAt,
      distance: presence.haversine(active.entry.lat, active.entry.lng, job.location.lat, job.location.lng),
    })).filter(job => job.distance <= active.entry.serviceRadius).slice(0, 100);
    if (!presence.current(active.entry)) throw fail(409, 'Availability changed');
    res.json({ success: true, data });
  } catch (err) { next(err); }
};

/**
 * GET /api/mechanics/profile
 * Returns the authenticated mechanic's profile with user data.
 */
const getProfile = async (req, res, next) => {
  try {
    const mechanic = await Mechanic.findOne({ userId: req.user.id })
      .select('userId skills serviceRadius shopAddress isApproved rating reviewCount totalJobs documents.status documents.rejectionReason approval')
      .populate('userId', 'name phone email role');

    if (!mechanic) {
      return res.status(404).json({ success: false, message: 'Mechanic profile not found' });
    }

    const statistics = await require('../services/history.service').summary({ mechanicId: mechanic._id });
    return res.status(200).json({ success: true, data: { statistics, accountApprovalStatus: require('../utils/profile-policy').approvalStatus(mechanic), ...(typeof mechanic.toObject === 'function' ? mechanic.toObject() : mechanic), totalJobs: statistics.completedJobs, serviceRadius: mechanic.serviceRadius ?? 15, isOnline: presence.isOnline(mechanic._id) } });
  } catch (err) {
    next(err);
  }
};

const updateProfile = async (req, res, next) => {
  const session = await require('mongoose').startSession();
  let id, approved;
  try {
    await session.withTransaction(async () => {
      const mechanic = await Mechanic.findOneAndUpdate({ userId: req.user.id }, { $inc: { __v: 1 } }, { new: true, session });
      if (!mechanic) throw fail(404, 'Mechanic profile not found');
      id = mechanic._id;
      if (req.body.name !== undefined) await require('../models/User').findByIdAndUpdate(req.user.id, { $set: { name: req.body.name.trim() } }, { session, runValidators: true });
      if (req.body.skills !== undefined) {
        const changed = JSON.stringify([...mechanic.skills].sort()) !== JSON.stringify([...req.body.skills].sort());
        mechanic.skills = req.body.skills;
        if (changed && mechanic.isApproved) {
          mechanic.isApproved = false;
          mechanic.documents ||= {};
          mechanic.approval = { status: 'pending' };
          // Existing document evidence is independent of account approval.
          if (!mechanic.documents.status) mechanic.documents.status = 'pending';
        }
      }
      if (req.body.serviceRadius !== undefined) mechanic.serviceRadius = req.body.serviceRadius;
      if (req.body.shopAddress !== undefined) mechanic.shopAddress = req.body.shopAddress.trim();
      await mechanic.save({ session });
      approved = mechanic.isApproved;
    });
    // Radius is reread by R04 discovery/dispatch/location validation. Only
    // qualification revocation removes otherwise legitimate online presence.
    if (!approved) presence.revoke(id);
    return getProfile(req, res, next);
  } catch (err) { next(err); }
  finally { await session.endSession(); }
};
module.exports = { getNearby, getProfile, getOpenRequests, updateProfile };
