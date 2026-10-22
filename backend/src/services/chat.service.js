const Job = require('../models/Job');
const Message = require('../models/Message');
const { assignmentFor } = require('./assignment.service');
const { sameId, authenticateAccessToken } = require('./access.service');
const fail = require('../utils/http-error');

async function participants(jobId, actor) {
  if (!['user', 'mechanic'].includes(actor.role)) throw fail(403, 'Job participant access required');
  const job = await Job.findById(jobId);
  if (!job) throw fail(404, 'Job not found');
  const assignment = await assignmentFor(job, actor);
  if (actor.role === 'user' && !sameId(actor.id, assignment.userId) ||
      actor.role === 'mechanic' && !sameId(actor.id, assignment.mechanicUserId)) {
    throw fail(403, 'Job participant access required');
  }
  return assignment;
}

const payload = message => ({
  _id: String(message._id), jobId: String(message.jobId), senderId: String(message.senderId),
  text: message.text, createdAt: message.createdAt,
});

async function list(req, res, next) {
  try {
    await participants(req.params.id, req.user);
    const limit = req.query.limit === undefined ? 30 : Number(req.query.limit);
    if (!Number.isInteger(limit) || limit < 1 || limit > 50 ||
        req.query.before !== undefined && !/^[a-f\d]{24}$/i.test(req.query.before) ||
        Object.keys(req.query).some(key => !['limit', 'before'].includes(key))) {
      throw fail(400, 'Invalid message pagination');
    }
    const filter = { jobId: req.params.id };
    if (req.query.before) filter._id = { $lt: req.query.before };
    const messages = await Message.find(filter).sort({ _id: -1 }).limit(limit + 1);
    const hasMore = messages.length > limit;
    const page = messages.slice(0, limit);
    const nextBefore = hasMore ? String(page[page.length - 1]._id) : null;
    res.json({ success: true, data: page.reverse().map(payload),
      nextBefore });
  } catch (err) { next(err); }
}

async function send(req, res, next) {
  try {
    const assignment = await participants(req.params.id, req.user);
    const text = req.body?.text;
    if (!req.body || Object.keys(req.body).length !== 1 || typeof text !== 'string' ||
        text.trim().length < 1 || text.length > 2000) throw fail(400, 'Message must contain 1–2000 characters');
    const message = await Message.create({ jobId: req.params.id, senderId: req.user.id, text: text.trim() });
    const saved = payload(message);
    const io = require('../socket/socket').getIo();
    if (io) {
      for (const socket of io.sockets.sockets.values()) {
        try {
          const actor = await authenticateAccessToken(socket.handshake.auth?.token);
          if (sameId(actor.id, assignment.userId) && actor.role === 'user' ||
              sameId(actor.id, assignment.mechanicUserId) && actor.role === 'mechanic' &&
              (await participants(req.params.id, actor))) socket.emit('chat:new', saved);
        } catch { /* Revoked sessions cannot receive private messages. */ }
      }
    }
    res.status(201).json({ success: true, data: saved });
  } catch (err) { next(err); }
}

module.exports = { participants, list, send };
