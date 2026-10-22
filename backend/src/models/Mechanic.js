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
    serviceRadius: { type: Number, default: 15, min: 1, max: 100 },
    shopAddress:   { type: String },
    lat:           { type: Number },
    lng:           { type: Number },
    isOnline:      { type: Boolean, default: false },
    isApproved:    { type: Boolean, default: false },
    approval: {
      status: { type: String, enum: ['pending', 'approved', 'rejected', 'revoked'], default: 'pending' },
      method: { type: String, enum: ['manual_profile_review'] },
      decidedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
      decidedAt: Date,
      reason: { type: String, maxlength: 500 },
    },
    rating:        { type: Number, default: 0, min: 0, max: 5 },
    reviewCount:   { type: Number, default: 0, min: 0 },
    totalJobs:     { type: Number, default: 0 },
    earnings:      { type: Number, default: 0 },
    verification: {
      status: { type: String, enum: ['draft', 'submitted', 'verified', 'rejected'], default: 'draft' },
      revision: { type: Number, default: 0 },
      licenseApplicable: { type: Boolean, default: false },
      workshopApplicable: { type: Boolean, default: false },
      permitNumber: { type: String, maxlength: 80 },
      submittedAt: Date,
      reviewedAt: Date,
      reason: { type: String, maxlength: 500 },
      files: [{
        kind: { type: String, enum: ['cnic_front', 'cnic_back', 'license', 'certificate', 'workshop'], required: true },
        fileId: { type: mongoose.Schema.Types.ObjectId, required: true },
        name: String, mime: String, size: Number, uploadedAt: Date,
      }],
    },
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

mechanicSchema.index({ isApproved: 1, 'approval.status': 1, createdAt: -1, _id: -1 });
module.exports = mongoose.model('Mechanic', mechanicSchema);
