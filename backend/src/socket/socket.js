const { Server } = require('socket.io');
const Job = require('../models/Job');
const Mechanic = require('../models/Mechanic');
const Bid = require('../models/Bid');
const { authenticateAccessToken, canViewJob, sameId, idPattern } = require('../services/access.service');
const { coordinates, object } = require('../middleware/request-validation');
const fail = require('../utils/http-error');
let io;
const presence = require('../services/presence.service');
const tracking = require('../services/job-tracking.service');
const getIo = () => io;
function revokeSession(sid) {
  if (!io) return;
  for (const namespace of io._nsps.values()) {
    for (const socket of namespace.sockets.values()) {
      if (socket.data.user?.sid === String(sid)) socket.disconnect(true);
    }
  }
}

function revokeAccount(userId) {
  if (!io) return;
  for (const namespace of io._nsps.values()) {
    for (const socket of namespace.sockets.values()) {
      if (sameId(socket.data.user?.id, userId)) {
        presence.disconnect(socket.id);
        socket.emit('security:error', { success: false, status: 403, message: 'Account access changed. Please sign in again.' });
        socket.disconnect(true);
      }
    }
  }
}
async function publishApproval(mechanic) {
  if (!io) return;
  await pruneJobRooms();
  io.to(`user_${mechanic.userId}`).emit('mechanic:approval_changed', {
    mechanicId: String(mechanic._id), isApproved: mechanic.isApproved,
    accountApprovalStatus: mechanic.isApproved ? 'approved' : mechanic.approval?.status || 'pending',
  });
}
async function handshake(socket, next) {
  try {
    socket.data.user = await authenticateAccessToken(socket.handshake.auth?.token);
    next();
  } catch (err) {
    const error = new Error('Socket authentication failed');
    error.data = { status: err.status === 403 ? 403 : 401 };
    next(error);
  }
}
function bind(socket, event, action) {
  socket.on(event, (data, acknowledge) => {
    const run = async () => {
    let authenticated = false;
    try {
      // Recheck persisted account state and expiry on every authorized operation.
      socket.data.user = await authenticateAccessToken(socket.handshake.auth?.token);
      authenticated = true;
      const result = await action(data, socket.data.user);
      if (typeof acknowledge === 'function') acknowledge({ success: true, data: result });
    } catch (err) {
      const response = { success: false, event, status: [400, 401, 403, 404, 409, 429].includes(err.status) ? err.status : 500,
        message: err.status ? err.message : 'Socket operation failed' };
      socket.emit('security:error', response);
      if (typeof acknowledge === 'function') acknowledge(response);
      if (response.status === 401 || response.status === 403 && (!authenticated || event.startsWith('mechanic:'))) {
        presence.disconnect(socket.id);
      }
      if (response.status === 401) socket.disconnect(true);
    }
    };
    if (event.startsWith('mechanic:')) {
      socket.data.presenceQueue = (socket.data.presenceQueue || Promise.resolve()).then(run, run);
    } else { run(); }
  });
}
function revokeMechanicPresence(mechanicId) {
  presence.revoke(mechanicId);
  // The admin mutation awaits revocation. Remove private
  // rooms as well; eligibility is also rechecked before each assignment emit.
  return pruneJobRooms();
}
async function pruneJobRooms() {
  if (!io) return;
  for (const socket of io.sockets.sockets.values()) {
    try {
      const actor = await authenticateAccessToken(socket.handshake.auth?.token);
      for (const room of [...socket.rooms].filter(name => name.startsWith('job_'))) {
        const job = await Job.findById(room.slice(4));
        if (!job || !await canViewJob(actor, job)) await socket.leave(room);
      }
    } catch { socket.disconnect(true); }
  }
}
function initSocket(server) {
  presence.clear();
  tracking.clearCache();
  tracking.sweep().catch(() => {});
  io = new Server(server, { cors: { origin: require('../utils/cors-origins')() }, maxHttpBufferSize: 100000 });
  const sweep = setInterval(() => { presence.eligibleEntries().catch(() => {}); tracking.sweep().catch(() => {}); }, 30000);
  sweep.unref();
  io.engine.on('close', () => { clearInterval(sweep); presence.clear(); tracking.clearCache(); });
  io.use(handshake);
  const admins = io.of('/admin');
  admins.use(handshake);
  admins.use((socket, next) => socket.data.user.role === 'admin' ? next() : next(new Error('Admin access required')));
  admins.on('connection', socket => {
    const timer = setTimeout(() => socket.disconnect(true), Math.max(0, socket.data.user.exp * 1000 - Date.now()));
    timer.unref();
    socket.on('disconnect', () => clearTimeout(timer));
  });
  io.on('connection', socket => {
    socket.join(`user_${socket.data.user.id}`);
    const timer = setTimeout(() => socket.disconnect(true), Math.max(0, socket.data.user.exp * 1000 - Date.now()));
    timer.unref();
    bind(socket, 'join_room', async (data, user) => {
      if (!object(data) || typeof data.room !== 'string') throw fail(400, 'Invalid room');
      if (data.room === `user_${user.id}`) { await socket.join(data.room); return; }
      if (!data.room.startsWith('job_')) throw fail(403, 'Room access forbidden');
      const id = data.room.slice(4);
      if (!idPattern.test(id)) throw fail(400, 'Invalid job room');
      const job = await Job.findById(id);
      if (!job) throw fail(404, 'Job not found');
      if (!await canViewJob(user, job)) throw fail(403, 'Job room access forbidden');
      await socket.join(data.room);
    });
    bind(socket, 'mechanic:go_online', (data, user) => presence.online(socket, user, data));
    bind(socket, 'mechanic:go_offline', (data, user) => presence.offline(socket, user, data));
    bind(socket, 'mechanic:update_location', (data, user) => presence.update(socket, user, data));
    bind(socket, 'job:mechanic_location', (data, user) => tracking.publish(user, data, io));
    for (const event of ['job:created', 'job:new_request', 'bid:new', 'bid:accepted',
      'job:assigned', 'job:unavailable', 'bid:declined',
      'job:status_changed', 'doc:status_update', 'mechanic:approval_changed', 'chat:new']) {
      bind(socket, event, async () => { throw fail(403, 'Server-generated event only'); });
    }
    bind(socket, 'sos:triggered', async (data, user) => {
      if (!coordinates(data)) throw fail(400, 'Invalid SOS coordinates');
      for (const admin of admins.sockets.values()) {
        try {
          const account = await authenticateAccessToken(admin.handshake.auth?.token);
          if (account.role !== 'admin') throw fail(403, 'Admin access required');
          admin.emit('sos:triggered', { userId: user.id, lat: data.lat, lng: data.lng });
        } catch { admin.disconnect(true); }
      }
    });
    socket.on('disconnect', () => { clearTimeout(timer); presence.disconnect(socket.id); });
  });
  return io;
}
function jobPayload(job, distance) {
  return { jobId: String(job._id), description: job.description, location: job.location,
    lat: job.location.lat, lng: job.location.lng, aiDiagnosis: job.aiDiagnosis,
    createdAt: job.createdAt, distance };
}
async function broadcastJobToMechanics(jobData) {
  if (!io || !idPattern.test(jobData?.jobId)) return;
  // Saved HTTP job data is authoritative, including its location and open state.
  const job = await Job.findById(jobData.jobId);
  if (!job || !['pending', 'bidding'].includes(job.status) || job.acceptedBidId || !coordinates(job.location)) return;
  for (const { entry, distance } of await presence.nearby(job.location.lat, job.location.lng)) {
    if (presence.current(entry)) io.to(entry.socket.id).emit('job:new_request', jobPayload(job, distance));
  }
}
async function publishAssignment(acceptedBid) {
  if (!io) return;
  const job = await Job.findById(acceptedBid.jobId);
  if (!job || !sameId(job.acceptedBidId, acceptedBid._id) || !sameId(job.mechanicId, acceptedBid.mechanicId)) return;
  const mechanic = await Mechanic.findById(job.mechanicId);
  if (!mechanic) return;
  const hint = { jobId: String(job._id), acceptedBidId: String(acceptedBid._id),
    mechanicId: String(mechanic._id), status: job.status };
  await pruneJobRooms();
  // Revalidate each live room member, not token role claims cached at handshake.
  // Only the owner and approved assigned mechanic receive private hints.
  const ownerRoom = `user_${job.userId}`, mechanicRoom = `user_${mechanic.userId}`;
  for (const socket of io.sockets.sockets.values()) {
    try {
      const actor = await authenticateAccessToken(socket.handshake.auth?.token);
      const owner = actor.role === 'user' && sameId(actor.id, job.userId);
      const winner = actor.role === 'mechanic' && sameId(actor.id, mechanic.userId) && await canViewJob(actor, job);
      if ((socket.rooms.has(ownerRoom) && !owner) || (socket.rooms.has(mechanicRoom) && !winner)) {
        await socket.leave(socket.rooms.has(ownerRoom) ? ownerRoom : mechanicRoom);
      }
      if (owner || winner) await socket.join(`job_${job._id}`);
      // Minimal invalidation only: never send customer/price data to opponents.
      if (actor.role === 'mechanic') socket.emit('job:unavailable', { jobId: String(job._id) });
    } catch { socket.disconnect(true); }
  }
  io.to(ownerRoom).emit('bid:accepted', hint);
  io.to(mechanicRoom).emit('job:assigned', hint);
  const bids = await Bid.find({ jobId: job._id, status: 'declined' });
  for (const bid of bids) {
    const losingMechanic = await Mechanic.findById(bid.mechanicId);
    if (losingMechanic) {
      io.to(`user_${losingMechanic.userId}`).emit('bid:declined', { jobId: String(job._id), bidId: String(bid._id), status: 'declined' });
    }
  }
}
async function publishJobStatus(job) {
  if (job.status !== 'en_route') tracking.clearJob(job._id);
  if (!io) return;
  const mechanic = job.mechanicId ? await Mechanic.findById(job.mechanicId) : null;
  const rooms = [`user_${job.userId}`, ...(mechanic ? [`user_${mechanic.userId}`] : [])];
  // Personal rooms are server-owned, but account/approval may have changed since
  // handshake. Remove stale members before the union emit (one delivery/socket).
  for (const socket of io.sockets.sockets.values()) {
    try {
      const actor = await authenticateAccessToken(socket.handshake.auth?.token);
      const owner = actor.role === 'user' && sameId(actor.id, job.userId);
      const assigned = actor.role === 'mechanic' && mechanic && sameId(actor.id, mechanic.userId) && await canViewJob(actor, job);
      for (const room of rooms) {
        const allowed = room === rooms[0] ? owner : assigned;
        if (socket.rooms.has(room) && !allowed) await socket.leave(room);
      }
    } catch { socket.disconnect(true); }
  }
  const payload = { jobId: String(job._id), status: job.status, version: job.statusVersion,
    changedAt: job.statusChangedAt, ...(job.updatedAt ? { updatedAt: job.updatedAt } : {}) };
  io.to(rooms).emit('job:status_changed', payload);
}
module.exports = { revokeAccount, publishApproval, revokeSession, initSocket, getIo, broadcastJobToMechanics, revokeMechanicPresence, jobPayload, publishAssignment, publishJobStatus };
