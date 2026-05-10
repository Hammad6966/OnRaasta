const mongoose = require('mongoose');

const mechanicSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      unique: true,
    },
    skills:        { type: [String], default: [] },
    serviceRadius: { type: Number, default: 15 },
    shopAddress:   { type: String },
    lat:           { type: Number },
    lng:           { type: Number },
    isOnline:      { type: Boolean, default: false },
    isApproved:    { type: Boolean, default: false },
    rating:        { type: Number, default: 0 },
    totalJobs:     { type: Number, default: 0 },
    earnings:      { type: Number, default: 0 },
    documents: {
      cnic_front:      { type: String },
      cnic_back:       { type: String },
      permit_number:   { type: String },
      permit_url:      { type: String },
      status: {
        type: String,
        enum: ['pending', 'verified', 'rejected'],
        default: 'pending',
      },
      rejectionReason: { type: String },
    },
  },
  { timestamps: true },
);

module.exports = mongoose.model('Mechanic', mechanicSchema);
