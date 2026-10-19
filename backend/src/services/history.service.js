const Job = require('../models/Job');
const Mechanic = require('../models/Mechanic');
const User = require('../models/User');
const { accounted, valid } = require('./accounting.service');
const fail = require('../utils/http-error');
const statuses = require('../middleware/request-validation').states;
function options(query, earnings = false) {
  if (Object.keys(query).some(k => !['page', 'limit', 'status', 'from', 'to'].includes(k))) throw fail(400, 'Unsupported history query');
  const integer = (value, fallback, max) => {
    if (value === undefined) return fallback;
    if (typeof value !== 'string' || !/^[1-9]\d*$/.test(value) || Number(value) > max) throw fail(400, 'Invalid pagination');
    return Number(value);
  };
  const page = integer(query.page, 1, 10000), limit = integer(query.limit, 20, 50);
  if (query.status !== undefined && (!['active', ...statuses].includes(query.status) || earnings && query.status !== 'completed')) throw fail(400, 'Invalid status filter');
  const date = value => {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) throw fail(400, 'Dates must use YYYY-MM-DD');
    const parsed = new Date(value + 'T00:00:00.000Z');
    if (!Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) throw fail(400, 'Invalid date');
    return parsed;
  };
  const from = query.from === undefined ? null : date(query.from), to = query.to === undefined ? null : date(query.to);
  if (from && to && (from > to || to - from > 3660 * 86400000)) throw fail(400, 'Invalid date range (maximum ten years)');
  const range = { ...(from ? { $gte: from } : {}), ...(to ? { $lte: new Date(to.getTime() + 86400000 - 1) } : {}) };
  return { page, limit, range, status: query.status };
}
async function scope(actor) {
  if (actor.role === 'user') return { userId: actor.id };
  if (actor.role !== 'mechanic') throw fail(403, 'Participant access required');
  const mechanic = await Mechanic.findOne({ userId: actor.id }).select('_id');
  if (!mechanic) throw fail(404, 'Mechanic profile not found');
  return { mechanicId: mechanic._id };
}
const empty = () => ({ completedJobs: 0, pricedJobs: 0, unpricedJobs: 0, grossMinor: 0n, commissionMinor: 0n, netMinor: 0n });
function add(total, job) {
  total.completedJobs++;
  if (!accounted(job)) { total.unpricedJobs++; return; }
  total.pricedJobs++;
  total.grossMinor += BigInt(job.accounting.totalMinor);
  total.commissionMinor += BigInt(job.accounting.commissionMinor);
  total.netMinor += BigInt(job.accounting.netMinor);
}
const serial = total => ({ ...total, grossMinor: String(total.grossMinor), commissionMinor: String(total.commissionMinor), netMinor: String(total.netMinor) });
async function summary(filter) {
  const result = empty(), buckets = new Map();
  for await (const job of Job.find({ ...filter, status: 'completed' }).select('status mechanicId acceptedBidId accounting completedAt').lean().cursor()) {
    add(result, job);
    if (job.completedAt && Number.isFinite(new Date(job.completedAt).getTime())) {
      const month = new Date(job.completedAt).toISOString().slice(0, 7);
      const bucket = buckets.get(month) || empty(); add(bucket, job); buckets.set(month, bucket);
    }
  }
  const months = [...buckets.keys()].sort().reverse();
  return { ...serial(result), months: months.slice(0, 24).map(month => ({ month, ...serial(buckets.get(month)) })), moreMonths: months.length > 24 };
}
async function row(job) {
  const fields = ['description', 'status', 'createdAt', 'completedAt', 'cancelledAt', 'acceptedBidId', 'mechanicId'];
  const data = { _id: String(job._id) };
  for (const key of fields) if (job[key] !== undefined) data[key] = job[key];
  const price = accounted(job) ? job.accounting : valid(job.agreedPricing, job.acceptedBidId) ? job.agreedPricing : null;
  data.pricingStatus = accounted(job) ? 'booked' : price ? 'agreed' : 'unavailable';
  if (price) data.pricing = { currency: 'PKR', labourMinor: price.labourMinor, partsMinor: price.partsMinor, totalMinor: price.totalMinor,
    ...(accounted(job) ? { commissionMinor: price.commissionMinor, netMinor: price.netMinor } : {}) };
  if (job.mechanicId) {
    const mechanic = await Mechanic.findById(job.mechanicId).select('userId shopAddress');
    const user = mechanic ? await User.findById(mechanic.userId).select('name') : null;
    data.mechanic = { _id: String(job.mechanicId), ...(user ? { name: user.name } : {}), ...(mechanic?.shopAddress ? { shopAddress: mechanic.shopAddress } : {}) };
  }
  return data;
}
async function list(req, res, next) {
  try {
    const o = options(req.query), filter = await scope(req.user);
    if (o.status === 'active') filter.status = { $in: statuses.filter(s => !['completed', 'cancelled'].includes(s)) };
    else if (o.status) filter.status = o.status;
    if (Object.keys(o.range).length) filter.createdAt = o.range;
    const [count, jobs] = await Promise.all([Job.countDocuments(filter), Job.find(filter).sort({ createdAt: -1, _id: -1 }).skip((o.page - 1) * o.limit).limit(o.limit)]);
    res.json({ success: true, data: await Promise.all(jobs.map(row)), pagination: { page: o.page, limit: o.limit, total: count, hasMore: o.page * o.limit < count } });
  } catch (err) { next(err); }
}
async function earnings(req, res, next) {
  try {
    if (req.user.role !== 'mechanic') throw fail(403, 'Mechanic access required');
    const o = options(req.query, true), owner = await scope(req.user);
    const filter = { ...owner, ...(Object.keys(o.range).length ? { completedAt: o.range } : {}) };
    const totals = await summary(filter);
    const jobs = await Job.find({ ...filter, status: 'completed' }).sort({ completedAt: -1, _id: -1 }).skip((o.page - 1) * o.limit).limit(o.limit);
    const undatedCompletedJobs = await Job.countDocuments({ ...owner, status: 'completed', completedAt: null });
    res.json({ success: true, data: { currency: 'PKR', basis: 'booked_not_paid', summary: totals, undatedCompletedJobs,
      jobs: await Promise.all(jobs.map(row)), pagination: { page: o.page, limit: o.limit, total: totals.completedJobs, hasMore: o.page * o.limit < totals.completedJobs } } });
  } catch (err) { next(err); }
}
module.exports = { list, earnings, summary, options, scope, row };
