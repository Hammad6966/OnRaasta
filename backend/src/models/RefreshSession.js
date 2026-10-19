const mongoose = require('mongoose');
const schema = new mongoose.Schema({
  userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  role: { type: String, enum: ['user', 'mechanic'], required: true },
  tokenHash: { type: String, required: true, select: false },
  previousHash: { type: String, select: false },
  rotatedAt: Date,
  revokedAt: { type: Date, default: null },
  expiresAt: { type: Date, required: true },
}, { timestamps: true });
schema.index({ expiresAt: 1 }, { expireAfterSeconds: 0, name: 'expired_refresh_sessions' });
module.exports = mongoose.model('RefreshSession', schema);
