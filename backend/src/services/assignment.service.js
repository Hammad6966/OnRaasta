const Job = require('../models/Job');
const Bid = require('../models/Bid');
const Mechanic = require('../models/Mechanic');
const User = require('../models/User');
const { approvedMechanic, canViewJob, sameId } = require('./access.service');
const fail = require('../utils/http-error');
const activeStatuses = ['accepted', 'en_route', 'arrived', 'in_progress'];
const pick = (value, fields) => Object.fromEntries(fields.filter(key => value?.[key] !== undefined).map(key => [key, value[key]]));

// Explicit projections: never serialize complete User/Mechanic documents.
async function assignmentFor(job, actor) {
  if (!await canViewJob(actor, job)) throw fail(403, 'Assignment access forbidden');
  if (actor.role === 'mechanic') await approvedMechanic(actor);
  if (!job.acceptedBidId || !job.mechanicId) throw fail(409, 'Job has no confirmed assignment');
  const bid = await Bid.findById(job.acceptedBidId);
  if (!bid || bid.status !== 'accepted' || !sameId(bid.jobId, job._id) || !sameId(bid.mechanicId, job.mechanicId)) {
    throw fail(409, 'Assignment records are inconsistent');
  }
  const mechanic = await Mechanic.findById(job.mechanicId);
  if (!mechanic) throw fail(409, 'Assigned mechanic profile is unavailable');
  const mechanicUser = await User.findById(mechanic.userId).select('name phone');
  const driver = await User.findById(job.userId).select('name phone');
  const publicMechanic = { ...pick(mechanic, ['skills', 'serviceRadius', 'shopAddress', 'isApproved', 'rating', 'reviewCount', 'totalJobs']),
    totalJobs: await Job.countDocuments({ mechanicId: mechanic._id, status: 'completed' }), _id: String(mechanic._id), userId: mechanicUser
      ? { _id: String(mechanic.userId), ...pick(mechanicUser, ['name', 'phone']) } : String(mechanic.userId) };
  const savedJob = { ...pick(job, ['status', 'location', 'description', 'aiDiagnosis', 'photos', 'vehicleId',
    'finalCost', 'agreedPricing', 'accounting', 'review', 'createdAt', 'updatedAt', 'statusVersion', 'statusChangedAt',
    'enRouteAt', 'arrivedAt', 'startedAt', 'completedAt', 'cancelledAt']), _id: String(job._id), userId: String(job.userId),
    mechanicId: String(job.mechanicId), acceptedBidId: String(job.acceptedBidId) };
  const accounting = require('./accounting.service');
  const price = accounting.accounted(job) ? job.accounting : job.agreedPricing;
  const frozen = accounting.valid(price, job.acceptedBidId) ? { labourCost: price.labourMinor / 100, partsCost: price.partsMinor / 100, totalCost: price.totalMinor / 100 } : {};
  const savedBid = { ...pick(bid, ['labourCost', 'partsCost', 'totalCost', 'eta', 'status', 'createdAt', 'updatedAt']),
    ...frozen, _id: String(bid._id), jobId: String(job._id), mechanicId: publicMechanic };
  return { jobId: savedJob._id, acceptedBidId: savedBid._id, mechanicId: String(mechanic._id),
    mechanicUserId: String(mechanic.userId), userId: String(job.userId), status: job.status,
    ...pick(bid, ['labourCost', 'partsCost', 'totalCost', 'eta']), ...frozen,
    job: savedJob, bid: savedBid, driver: { _id: String(job.userId), ...pick(driver, ['name', 'phone']) } };
}
async function getAssignment(req, res, next) {
  try {
    const job = await Job.findById(req.params.id);
    if (!job) throw fail(404, 'Job not found');
    res.json({ success: true, data: await assignmentFor(job, req.user) });
  } catch (err) { next(err); }
}
async function listAssignments(req, res, next) {
  try {
    let filter;
    if (req.user.role === 'user') filter = { userId: req.user.id };
    else if (req.user.role === 'mechanic') filter = { mechanicId: (await approvedMechanic(req.user))._id };
    else throw fail(403, 'Participant access required');
    if (req.query.includeClosed !== undefined && !['true', 'false'].includes(req.query.includeClosed)) throw fail(400, 'Invalid assignment recovery query');
    const jobs = await Job.find({ ...filter, status: { $in: activeStatuses }, acceptedBidId: { $ne: null } }).sort({ createdAt: -1 });
    if (req.query.includeClosed === 'true') {
      const closed = await Job.find({ ...filter, status: { $in: ['completed', 'cancelled'] }, acceptedBidId: { $ne: null } }).sort({ updatedAt: -1, _id: -1 }).limit(10);
      jobs.push(...closed.slice(0, 10));
    }
    // Stable ordering and all assignments: no silent replacement by the last job.
    jobs.sort((a, b) => (new Date(b.createdAt || 0) - new Date(a.createdAt || 0)) || String(a._id).localeCompare(String(b._id)));
    const data = [];
    for (const job of jobs) data.push(await assignmentFor(job, req.user));
    res.json({ success: true, data });
  } catch (err) { next(err); }
}
async function opportunity(req, res, next) {
  try {
    await approvedMechanic(req.user);
    const job = await Job.findById(req.params.id);
    if (!job) throw fail(404, 'Job not found');
    // Only availability is public to bidders; no assigned customer data.
    res.json({ success: true, data: { jobId: String(job._id),
      isOpen: ['pending', 'bidding'].includes(job.status) && !job.acceptedBidId } });
  } catch (err) { next(err); }
}
module.exports = { assignmentFor, getAssignment, listAssignments, opportunity, activeStatuses };
