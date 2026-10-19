const mongoose = require('mongoose');
const state = new mongoose.Schema({
  isActive: Boolean, isApproved: Boolean,
  approvalStatus: { type: String, enum: ['pending', 'approved', 'rejected', 'revoked'] },
}, { _id: false, strict: 'throw' });
const schema = new mongoose.Schema({
  adminId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, immutable: true },
  targetId: { type: mongoose.Schema.Types.ObjectId, required: true, immutable: true },
  targetType: { type: String, enum: ['User', 'Mechanic'], required: true, immutable: true },
  action: { type: String, enum: ['account_suspended', 'account_reactivated', 'mechanic_approved', 'mechanic_rejected', 'mechanic_revoked'], required: true, immutable: true },
  previous: { type: state, required: true, immutable: true },
  next: { type: state, required: true, immutable: true },
  reason: { type: String, required: true, minlength: 3, maxlength: 500, immutable: true },
  createdAt: { type: Date, default: Date.now, required: true, immutable: true },
}, { strict: 'throw', versionKey: false });
schema.index({ createdAt: -1, _id: -1 });
schema.index({ targetId: 1, createdAt: -1 });
module.exports = mongoose.model('AdminLog', schema);
