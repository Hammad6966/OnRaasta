const mongoose = require('mongoose');
const User = require('../models/User');
const Mechanic = require('../models/Mechanic');
const AdminLog = require('../models/AdminLog');
const RefreshSession = require('../models/RefreshSession');
const fail = require('../utils/http-error');
const sockets = require('../socket/socket');
const { authenticateAccessToken, sameId } = require('./access.service');
const { object } = require('../middleware/request-validation');
const { approvalStatus } = require('../utils/profile-policy');
const safeUser = u => ({ _id: String(u._id), name: u.name, email: u.email, phone: u.phone, role: u.role,
  isActive: u.isActive, isVerified: u.isVerified, createdAt: u.createdAt, updatedAt: u.updatedAt, revision: u.__v || 0 });
function safeMechanic(m) {
  return { _id: String(m._id), userId: String(m.userId), skills: m.skills || [], serviceRadius: m.serviceRadius ?? 15,
    shopAddress: m.shopAddress, rating: m.rating, reviewCount: m.reviewCount, isApproved: m.isApproved,
    accountApprovalStatus: approvalStatus(m), revision: m.__v || 0, createdAt: m.createdAt, updatedAt: m.updatedAt,
    approval: m.approval ? { method: m.approval.method, decidedAt: m.approval.decidedAt, decidedBy: m.approval.decidedBy, reason: m.approval.reason } : null,
    documents: { status: m.documents?.status || 'pending', evidenceAvailable: Boolean(m.documents?.cnic_front && m.documents?.cnic_back), verificationAvailable: false } };
}
const version = doc => doc.__v === undefined ? { $exists: false } : doc.__v;
function options(q, allowed = []) {
  if (Object.keys(q).some(k => !['page', 'limit', 'search', ...allowed].includes(k))) throw fail(400, 'Unsupported query');
  const number = (s, def, max) => {
    if (s === undefined) return def;
    if (typeof s !== 'string' || !/^[1-9]\d*$/.test(s) || Number(s) > max) throw fail(400, 'Invalid pagination');
    return Number(s);
  };
  const page = number(q.page, 1, 200), limit = number(q.limit, 20, 50);
  const search = q.search === undefined ? '' : q.search;
  if (typeof search !== 'string' || search.length > 80 || /[\x00-\x1f]/.test(search)) throw fail(400, 'Invalid search');
  if (q.role !== undefined && !['user', 'mechanic'].includes(q.role)) throw fail(400, 'Invalid role');
  if (q.active !== undefined && !['true', 'false'].includes(q.active)) throw fail(400, 'Invalid active filter');
  if (q.approval !== undefined && !['pending', 'approved', 'rejected', 'revoked'].includes(q.approval)) throw fail(400, 'Invalid approval filter');
  const filter = { role: q.role || { $in: ['user', 'mechanic'] } };
  if (q.active !== undefined) filter.isActive = q.active === 'true';
  if (search.trim()) {
    const prefix = '^' + search.trim().replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    filter.$or = ['name', 'email', 'phone'].map(k => ({ [k]: { $regex: prefix, $options: 'i' } }));
  }
  return { page, limit, filter };
}
function approvalFilter(status) {
  if (status === 'approved') return { isApproved: true };
  if (status === 'pending') return { isApproved: false, $or: [{ 'approval.status': 'pending' }, { 'approval.status': { $exists: false } }] };
  return { isApproved: false, 'approval.status': status };
}
const pagination = (o, total) => ({ page: o.page, limit: o.limit, total, hasMore: o.page * o.limit < total });
async function listUsers(req, res, next) {
  try {
    const o = options(req.query, ['role', 'active', 'approval']);
    if (req.query.approval) {
      const profiles = await Mechanic.find(approvalFilter(req.query.approval)).select('userId').limit(1001);
      if (profiles.length > 1000) throw fail(400, 'Narrow approval filtering through the applications list');
      o.filter._id = { $in: profiles.map(m => m.userId) };
      if (req.query.role === 'user') o.filter._id = { $in: [] };
      else o.filter.role = 'mechanic';
    }
    const [total, users] = await Promise.all([User.countDocuments(o.filter), User.find(o.filter).select('name email phone role isVerified isActive createdAt updatedAt __v').sort({ createdAt: -1, _id: -1 }).skip((o.page - 1) * o.limit).limit(o.limit)]);
    const data = await Promise.all(users.map(async u => ({ ...safeUser(u), mechanic: u.role === 'mechanic' ? await Mechanic.findOne({ userId: u._id }).then(m => m ? safeMechanic(m) : null) : null })));
    res.json({ success: true, data, pagination: pagination(o, total) });
  } catch (e) { next(e); }
}
async function detail(req, res, next) {
  try {
    const u = await User.findById(req.params.id);
    if (!u || !['user', 'mechanic'].includes(u.role)) throw fail(404, 'Account not found');
    const m = u.role === 'mechanic' ? await Mechanic.findOne({ userId: u._id }) : null;
    res.json({ success: true, data: { ...safeUser(u), mechanic: m ? safeMechanic(m) : null } });
  } catch (e) { next(e); }
}
async function applicationCounts() {
  const counts = { pending: 0, approved: 0, rejected: 0, revoked: 0, eligibleApproved: 0 };
  for await (const m of Mechanic.find().lean().cursor()) {
    const u = await User.findById(m.userId).select('role isActive isVerified');
    if (!u || u.role !== 'mechanic') continue;
    counts[approvalStatus(m)]++;
    if (m.isApproved && u.isActive && u.isVerified) counts.eligibleApproved++;
  }
  return counts;
}
async function applications(req, res, next) {
  try {
    const o = options(req.query, ['approval', 'active']);
    const filter = req.query.approval ? approvalFilter(req.query.approval) : {};
    // Search/active filters resolve only mechanic accounts and stay bounded.
    if (req.query.search || req.query.active !== undefined) {
      const users = await User.find({ ...o.filter, role: 'mechanic' }).select('_id').limit(1001);
      if (users.length > 1000) throw fail(400, 'Narrow the application search');
      filter.userId = { $in: users.map(u => u._id) };
    }
    const [total, profiles, counts] = await Promise.all([Mechanic.countDocuments(filter), Mechanic.find(filter).sort({ createdAt: -1, _id: -1 }).skip((o.page - 1) * o.limit).limit(o.limit), applicationCounts()]);
    const data = await Promise.all(profiles.map(async m => {
      const u = await User.findById(m.userId);
      return u?.role === 'mechanic' ? { ...safeMechanic(m), user: safeUser(u) } : null;
    }));
    res.json({ success: true, data: data.filter(Boolean), pagination: pagination(o, total), counts });
  } catch (e) { next(e); }
}
function mutation(body, keys) {
  if (!object(body) || Object.keys(body).some(k => !keys.includes(k)) || !Number.isSafeInteger(body.expectedVersion) || body.expectedVersion < 0 ||
      typeof body.reason !== 'string' || body.reason.trim().length < 3 || body.reason.length > 500 || /[\x00-\x1f<>]/.test(body.reason)) throw fail(400, 'Provide a reason (3-500 characters) and current expectedVersion');
}
async function actorLock(req, session) {
  const actor = await authenticateAccessToken(req.headers.authorization?.slice(7));
  if (actor.role !== 'admin' || !sameId(actor.id, req.user.id)) throw fail(403, 'Administrator required');
  const locked = await User.findOneAndUpdate({ _id: actor.id, role: 'admin', isActive: true, isVerified: true }, { $inc: { __v: 1 } }, { new: true, session });
  if (!locked) throw fail(403, 'Administrator unavailable');
}
async function transaction(work) {
  const session = await mongoose.startSession();
  try { let result; await session.withTransaction(async () => { result = await work(session); }); return result; }
  finally { await session.endSession(); }
}
async function audit(req, session, target, type, action, previous, next) {
  await AdminLog.create([{ adminId: req.user.id, targetId: target._id, targetType: type, action, previous, next, reason: req.body.reason.trim(), createdAt: new Date() }], { session });
}
async function accountStatus(req, res, next) {
  try {
    mutation(req.body, ['isActive', 'reason', 'expectedVersion']);
    if (typeof req.body.isActive !== 'boolean') throw fail(400, 'Invalid account status');
    const result = await transaction(async session => {
      await actorLock(req, session);
      const user = await User.findById(req.params.id).session(session);
      if (!user) throw fail(404, 'Account not found');
      if (!['user', 'mechanic'].includes(user.role) || sameId(user._id, req.user.id)) throw fail(403, 'Only driver and mechanic accounts may be managed');
      if ((user.__v || 0) !== req.body.expectedVersion || user.isActive === req.body.isActive) throw fail(409, 'Account changed; refresh before retrying');
      const updated = await User.findOneAndUpdate({ _id: user._id, __v: version(user), isActive: user.isActive }, { $set: { isActive: req.body.isActive }, $inc: { __v: 1 } }, { new: true, session, runValidators: true });
      if (!updated) throw fail(409, 'Account changed; refresh before retrying');
      const mechanic = user.role === 'mechanic' ? await Mechanic.findOneAndUpdate({ userId: user._id }, { $inc: { __v: 1 }, ...(!req.body.isActive ? { $set: { isOnline: false } } : {}) }, { new: true, session }) : null;
      if (!req.body.isActive) await RefreshSession.updateMany({ userId: user._id, revokedAt: null }, { $set: { revokedAt: new Date() } }, { session });
      await audit(req, session, user, 'User', req.body.isActive ? 'account_reactivated' : 'account_suspended', { isActive: user.isActive }, { isActive: updated.isActive });
      return { user: updated, mechanic };
    });
    // Persistence has committed. A notification failure must not reverse success.
    if (!result.user.isActive) {
      if (result.mechanic) { require('./presence.service').revoke(result.mechanic._id); }
      sockets.revokeAccount(result.user._id);
    }
    res.json({ success: true, data: { ...safeUser(result.user), mechanic: result.mechanic ? safeMechanic(result.mechanic) : null } });
  } catch (e) { next(e); }
}
async function decide(req, res, next) {
  try {
    mutation(req.body, ['action', 'reason', 'expectedVersion']);
    if (!['approve', 'reject', 'revoke'].includes(req.body.action)) throw fail(400, 'Invalid approval action; document verification is deferred');
    const m = await transaction(async session => {
      await actorLock(req, session);
      const previous = await Mechanic.findById(req.params.mechanicId).session(session);
      if (!previous) throw fail(404, 'Mechanic not found');
      if ((previous.__v || 0) !== req.body.expectedVersion) throw fail(409, 'Application changed; refresh before retrying');
      const user = await User.findOneAndUpdate({ _id: previous.userId, role: 'mechanic' }, { $inc: { __v: 1 } }, { new: true, session });
      if (!user) throw fail(404, 'Mechanic account not found');
      const before = approvalStatus(previous), action = req.body.action;
      if (action === 'approve' && (!user.isActive || !user.isVerified)) throw fail(409, 'An active verified mechanic account is required');
      if (action === 'approve' && before === 'approved' || action === 'reject' && before !== 'pending' || action === 'revoke' && before !== 'approved') throw fail(409, 'Invalid approval transition; refresh application');
      const status = { approve: 'approved', reject: 'rejected', revoke: 'revoked' }[action];
      const updated = await Mechanic.findOneAndUpdate({ _id: previous._id, __v: version(previous) }, { $set: {
        isApproved: action === 'approve', ...(action !== 'approve' ? { isOnline: false } : {}),
        approval: { status, method: 'manual_profile_review', decidedBy: req.user.id, decidedAt: new Date(), reason: req.body.reason.trim() },
      }, $inc: { __v: 1 } }, { new: true, session, runValidators: true });
      if (!updated) throw fail(409, 'Application changed; refresh before retrying');
      await audit(req, session, previous, 'Mechanic', `mechanic_${status}`, { isApproved: previous.isApproved, approvalStatus: before }, { isApproved: updated.isApproved, approvalStatus: status });
      return updated;
    });
    if (!m.isApproved) require('./presence.service').revoke(m._id);
    try { await sockets.revokeMechanicPresence(m._id); await sockets.publishApproval(m); } catch { /* HTTP reload remains authoritative. */ }
    res.json({ success: true, data: safeMechanic(m) });
  } catch (e) { next(e); }
}
async function logs(req, res, next) {
  try {
    const o = options(req.query, ['targetId']);
    if (req.query.search !== undefined) throw fail(400, 'Search is unavailable for audit records');
    const filter = {};
    if (req.query.targetId !== undefined) {
      if (typeof req.query.targetId !== 'string' || !require('./access.service').idPattern.test(req.query.targetId)) throw fail(400, 'Invalid target ID');
      filter.targetId = req.query.targetId;
    }
    const [total, data] = await Promise.all([AdminLog.countDocuments(filter), AdminLog.find(filter).sort({ createdAt: -1, _id: -1 }).skip((o.page - 1) * o.limit).limit(o.limit).lean()]);
    res.json({ success: true, data, pagination: pagination(o, total) });
  } catch (e) { next(e); }
}
module.exports = { listUsers, detail, applications, decide, accountStatus, logs, safeUser, safeMechanic, approvalStatus, applicationCounts };
