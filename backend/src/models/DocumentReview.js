const mongoose = require('mongoose');
const schema = new mongoose.Schema({
  mechanicId: { type: mongoose.Schema.Types.ObjectId, ref: 'Mechanic', required: true, immutable: true },
  actorId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, immutable: true },
  action: { type: String, enum: ['submitted', 'verified', 'rejected'], required: true, immutable: true },
  revision: { type: Number, required: true, immutable: true },
  reason: { type: String, maxlength: 500, immutable: true },
  files: [{ kind: String, fileId: mongoose.Schema.Types.ObjectId }],
  createdAt: { type: Date, default: Date.now, immutable: true },
}, { versionKey: false });
schema.index({ mechanicId: 1, createdAt: -1 });
module.exports = mongoose.model('DocumentReview', schema);
