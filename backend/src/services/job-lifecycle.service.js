const mongoose = require('mongoose');
const Job = require('../models/Job');
const User = require('../models/User');
const { approvedMechanic, sameId } = require('./access.service');
const fail = require('../utils/http-error');

const transitions = Object.freeze({ accepted: 'en_route', en_route: 'arrived', arrived: 'in_progress', in_progress: 'completed' });
const milestones = Object.freeze({ en_route: 'enRouteAt', arrived: 'arrivedAt', in_progress: 'startedAt', completed: 'completedAt', cancelled: 'cancelledAt' });

async function transitionJob(user, id, input) {
  // Capture the original snapshot outside retry callbacks. A retried transaction
  // must not reinterpret a stale request as permission for a later stage.
  const initial = await Job.findById(id);
  if (!initial) throw fail(404, 'Job not found');
  const session = await mongoose.startSession();
  try {
    return await session.withTransaction(async () => {
      const account = await User.findOneAndUpdate({ _id: user.id, role: user.role, isActive: true, isVerified: true },
        { $inc: { __v: 1 } }, { new: true, session });
      if (!account) throw fail(403, 'Account is inactive or unverified');
      const current = await Job.findById(id).session(session);
      if (!current) throw fail(404, 'Job not found');
      if (input.status === 'cancelled') {
        if (user.role !== 'admin' && !(user.role === 'user' && sameId(current.userId, user.id))) throw fail(403, 'Cancellation forbidden');
      } else {
        const mechanic = await approvedMechanic(user, session);
        if (!sameId(current.mechanicId, mechanic._id)) throw fail(403, 'Assigned mechanic access required');
      }
      if (['completed', 'cancelled'].includes(current.status)) throw fail(409, 'Job is already closed');
      if (current.status !== initial.status || (current.statusVersion ?? 0) !== (initial.statusVersion ?? 0) ||
          !sameNullable(current.mechanicId, initial.mechanicId) || !sameNullable(current.acceptedBidId, initial.acceptedBidId) ||
          (input.expectedStatus !== undefined && current.status !== input.expectedStatus) ||
          (input.expectedVersion !== undefined && (current.statusVersion ?? 0) !== input.expectedVersion)) throw fail(409, 'Job state changed; reload and try again');
      if (input.status === 'cancelled') {
        if (user.role !== 'admin' && !['pending', 'bidding', 'accepted', 'en_route'].includes(current.status)) throw fail(409, 'Job cannot be cancelled at this stage');
      } else if (transitions[current.status] !== input.status) throw fail(409, 'Invalid job status transition');
      const now = new Date();
      const accounting = input.status === 'completed' ? await require('./accounting.service').finalize(current, session, now) : undefined;
      const job = await Job.findOneAndUpdate({ _id: current._id, status: current.status,
        mechanicId: current.mechanicId ?? null, acceptedBidId: current.acceptedBidId ?? null,
        // Old records without the new field are equivalent to version zero.
        $or: [{ statusVersion: current.statusVersion ?? 0 }, { statusVersion: { $exists: false } }] },
      { $set: { status: input.status, statusChangedAt: now, ...(accounting ? { accounting } : {}), [milestones[input.status]]: now, ...(input.status !== 'en_route' ? { latestMechanicLocation: null } : {}) },
        $inc: { statusVersion: 1 } }, { new: true, session, runValidators: true });
      if (!job) throw fail(409, 'Job state changed; reload and try again');
      // Completion snapshot and status commit together. Legacy mechanic earnings
      // counters are not financial truth; reports derive completed snapshots.
      return job;
    });
  } finally { await session.endSession(); }
}
const sameNullable = (a, b) => a == null && b == null || sameId(a, b);
module.exports = { transitionJob, transitions };
