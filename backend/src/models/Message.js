const mongoose = require('mongoose');

const messageSchema = new mongoose.Schema({
  jobId: { type: mongoose.Schema.Types.ObjectId, ref: 'Job', required: true },
  senderId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  text: { type: String, required: true, minlength: 1, maxlength: 2000 },
}, { timestamps: true });

messageSchema.index({ jobId: 1, createdAt: -1, _id: -1 });
module.exports = mongoose.model('Message', messageSchema);
