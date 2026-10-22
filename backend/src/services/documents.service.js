const mongoose = require('mongoose');
const Mechanic = require('../models/Mechanic');
const User = require('../models/User');
const Review = require('../models/DocumentReview');
const media = require('./media.service');
const fail = require('../utils/http-error');
const kinds = ['cnic_front', 'cnic_back', 'license', 'certificate', 'workshop'];
const version = m => m.__v === undefined ? { $exists: false } : m.__v;
const value = m => ({ mechanicId: String(m._id), expectedVersion: m.__v || 0,
  ...(m.verification?.toObject ? m.verification.toObject() : m.verification || { status: 'draft', revision: 0, files: [] }) });
exports.value = value;
exports.required = v => ['cnic_front', 'cnic_back', 'certificate', ...(v.licenseApplicable ? ['license'] : []), ...(v.workshopApplicable ? ['workshop'] : [])];
async function profile(req, session) {
  const m = await (req.user.role === 'admin' ? Mechanic.findById(req.params.mechanicId) : Mechanic.findOne({ userId: req.user.id })).session(session || null);
  if (!m) throw fail(404, 'Mechanic profile not found');
  return m;
}
async function replace(m, patch, session) {
  const updated = await Mechanic.findOneAndUpdate({ _id: m._id, __v: version(m) }, { $set: patch, $inc: { __v: 1 } }, { new: true, runValidators: true, session });
  if (!updated) throw fail(409, 'Documents changed. Reload before retrying.');
  return updated;
}
exports.get = async (req, res, next) => {
  try {
    const m = await profile(req);
    const history = await Review.find({ mechanicId: m._id }).sort({ createdAt: -1, _id: -1 }).limit(100).lean();
    res.json({ success: true, data: { ...value(m), history } });
  } catch (e) { next(e); }
};
exports.upload = async (req, res, next) => {
  try {
    if (!kinds.includes(req.params.kind)) throw fail(400, 'Unknown document section');
    const m = await profile(req);
    if (Number(req.body.expectedVersion) !== (m.__v || 0) || !/^\d+$/.test(String(req.body.expectedVersion))) throw fail(409, 'Reload current documents before uploading');
    const { buffer, ...info } = await media.prepare(req.file, !req.params.kind.startsWith('cnic'));
    const fileId = await media.store(buffer, { ...info, purpose: 'document', ownerId: req.user.id, mechanicId: String(m._id), kind: req.params.kind });
    const files = (value(m).files || []).filter(f => f.kind !== req.params.kind);
    files.push({ ...info, fileId, kind: req.params.kind, uploadedAt: new Date() });
    const updated = await replace(m, { 'verification.files': files, 'verification.status': 'draft', 'verification.reason': '', 'documents.status': 'pending', 'documents.rejectionReason': '', 'verification.revision': (m.verification?.revision || 0) + 1 });
    res.status(201).json({ success: true, data: value(updated) });
  } catch (e) { next(e); }
};
exports.submit = async (req, res, next) => {
  const session = await mongoose.startSession();
  try {
    const b = req.body;
    if (!b || Object.keys(b).some(k => !['expectedVersion', 'licenseApplicable', 'workshopApplicable', 'permitNumber'].includes(k)) || !Number.isSafeInteger(b.expectedVersion) || typeof b.licenseApplicable !== 'boolean' || typeof b.workshopApplicable !== 'boolean' || typeof b.permitNumber !== 'string' || b.permitNumber.length > 80 || /[<>\x00-\x1f]/.test(b.permitNumber)) throw fail(400, 'Provide document applicability, permit number and current version');
    let updated;
    await session.withTransaction(async () => {
      const owner = await User.findOneAndUpdate({ _id: req.user.id, role: 'mechanic', isActive: true, isVerified: true }, { $inc: { __v: 1 } }, { new: true, session });
      if (!owner) throw fail(403, 'Account unavailable');
      const m = await profile(req, session), v = value(m);
      if (v.expectedVersion !== b.expectedVersion || !['draft', 'rejected'].includes(v.status)) throw fail(409, 'Documents changed or already submitted. Reload first.');
      if (exports.required(b).some(kind => !(v.files || []).some(f => f.kind === kind)) || b.workshopApplicable && !b.permitNumber.trim()) throw fail(400, 'Upload every required document and enter the applicable workshop permit number');
      updated = await replace(m, { 'verification.status': 'submitted', 'verification.licenseApplicable': b.licenseApplicable, 'verification.workshopApplicable': b.workshopApplicable, 'verification.permitNumber': b.permitNumber.trim(), 'verification.submittedAt': new Date(), 'verification.reason': '' }, session);
      await Review.create([{ mechanicId: m._id, actorId: req.user.id, action: 'submitted', revision: v.revision, files: v.files.map(f => ({ kind: f.kind, fileId: f.fileId })) }], { session });
    });
    res.json({ success: true, data: value(updated) });
  } catch (e) { next(e); } finally { await session.endSession(); }
};
exports.review = async (req, res, next) => {
  const session = await mongoose.startSession();
  try {
    const b = req.body;
    if (!b || Object.keys(b).some(k => !['expectedVersion', 'action', 'reason'].includes(k)) || !Number.isSafeInteger(b.expectedVersion) || !['verified', 'rejected'].includes(b.action) || typeof b.reason !== 'string' || b.reason.trim().length < 3 || b.reason.length > 500 || /[<>\x00-\x1f]/.test(b.reason)) throw fail(400, 'Provide a review decision, reason (3–500 characters) and current version');
    let updated;
    await session.withTransaction(async () => {
      await require('./admin.service').actorLock(req, session);
      const m = await profile(req, session), v = value(m);
      if (v.expectedVersion !== b.expectedVersion || v.status !== 'submitted') throw fail(409, 'This submission changed or has already been reviewed');
      if (b.action === 'verified' && exports.required(v).some(kind => !v.files.some(f => f.kind === kind))) throw fail(409, 'Required documents are missing');
      updated = await replace(m, { 'verification.status': b.action, 'verification.reason': b.reason.trim(), 'verification.reviewedAt': new Date(), 'documents.status': b.action === 'verified' ? 'verified' : 'rejected', 'documents.rejectionReason': b.action === 'rejected' ? b.reason.trim() : '' }, session);
      await Review.create([{ mechanicId: m._id, actorId: req.user.id, action: b.action, reason: b.reason.trim(), revision: v.revision, files: v.files.map(f => ({ kind: f.kind, fileId: f.fileId })) }], { session });
    });
    res.json({ success: true, data: value(updated) });
  } catch (e) { next(e); } finally { await session.endSession(); }
};
