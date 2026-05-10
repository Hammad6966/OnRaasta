const mongoose = require('mongoose');

const otpStoreSchema = new mongoose.Schema({
  phone:     { type: String, required: true },
  otp:       { type: String },
  expiresAt: { type: Date },
  attempts:  { type: Number, default: 0 },
  createdAt: { type: Date, default: Date.now, expires: 300 }, // TTL 300 s
});

module.exports = mongoose.model('OtpStore', otpStoreSchema);
