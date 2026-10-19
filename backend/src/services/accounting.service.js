const Bid = require('../models/Bid');
const { sameId } = require('./access.service');
const fail = require('../utils/http-error');
// Convert the persisted decimal representation, never multiply binary fractions.
function minor(value) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 2e8) throw fail(409, 'Agreed pricing is unavailable');
  const match = /^(\d+)(?:\.(\d{1,2}))?$/.exec(String(value));
  if (!match) throw fail(409, 'Agreed pricing must have at most two decimal places');
  return Number(BigInt(match[1]) * 100n + BigInt((match[2] || '').padEnd(2, '0')));
}
function pricing(bid) {
  const labourMinor = minor(bid.labourCost), partsMinor = minor(bid.partsCost ?? 0), totalMinor = minor(bid.totalCost);
  if (labourMinor < 50000 || labourMinor > 1e10 || partsMinor > 1e10 || labourMinor + partsMinor !== totalMinor) throw fail(409, 'Agreed pricing components are inconsistent');
  return { currency: 'PKR', version: 1, acceptedBidId: bid._id, labourMinor, partsMinor, totalMinor };
}
function valid(price, bidId) {
  return price?.currency === 'PKR' && price.version === 1 && sameId(price.acceptedBidId, bidId) &&
    ['labourMinor', 'partsMinor', 'totalMinor'].every(k => Number.isSafeInteger(price[k]) && price[k] >= 0 && price[k] <= 2e10) &&
    price.labourMinor >= 50000 && price.labourMinor <= 1e10 && price.partsMinor <= 1e10 && price.labourMinor + price.partsMinor === price.totalMinor;
}
function completedSnapshot(price, at) {
  if (!valid(price, price?.acceptedBidId)) throw fail(409, 'Agreed pricing is unavailable');
  const commissionMinor = Number((BigInt(price.totalMinor) * 15n + 50n) / 100n);
  return { currency: 'PKR', version: 1, acceptedBidId: price.acceptedBidId, labourMinor: price.labourMinor, partsMinor: price.partsMinor, totalMinor: price.totalMinor, commissionBps: 1500, commissionMinor, netMinor: price.totalMinor - commissionMinor, recordedAt: at };
}
function accounted(job) {
  const p = job.accounting;
  if (job.status !== 'completed' || !job.mechanicId || !job.acceptedBidId || !valid(p, job.acceptedBidId) ||
      p.commissionBps !== 1500 || !p.recordedAt || !Number.isFinite(new Date(p.recordedAt).getTime())) return false;
  const expected = completedSnapshot(p, p.recordedAt);
  return p.commissionMinor === expected.commissionMinor && p.netMinor === expected.netMinor;
}
async function finalize(job, session, now) {
  const bid = await Bid.findById(job.acceptedBidId).session(session);
  if (!bid || bid.status !== 'accepted' || !sameId(bid.jobId, job._id) || !sameId(bid.mechanicId, job.mechanicId)) throw fail(409, 'Confirmed pricing assignment is unavailable');
  if (accounted({ ...((typeof job.toObject === 'function') ? job.toObject() : job), status: 'completed' })) return job.accounting;
  const agreed = job.agreedPricing;
  if (agreed && !valid(agreed, job.acceptedBidId)) throw fail(409, 'Agreed pricing snapshot is inconsistent');
  const selected = agreed || pricing(bid);
  return completedSnapshot({ currency: selected.currency, version: selected.version, acceptedBidId: selected.acceptedBidId,
    labourMinor: selected.labourMinor, partsMinor: selected.partsMinor, totalMinor: selected.totalMinor }, now);
}
module.exports = { minor, pricing, valid, completedSnapshot, accounted, finalize };
