const mongoose = require('mongoose');

const jobSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    mechanicId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Mechanic',
    },
    status: {
      type: String,
      enum: [
        'pending', 'bidding', 'accepted',
        'en_route', 'arrived', 'in_progress',
        'completed', 'cancelled',
      ],
      default: 'pending',
    },
    location: {
      lat:     { type: Number, required: true },
      lng:     { type: Number, required: true },
      address: { type: String },
    },
    description: { type: String, required: true },
    aiDiagnosis: {
      fault_class:   { type: String },
      confidence:    { type: Number },
      cost_min:      { type: Number },
      cost_max:      { type: Number },
      skill_required:{ type: String },
    },
    photos: {
      type: [String],
      validate: {
        validator: (arr) => arr.length <= 3,
        message: 'Maximum 3 photos allowed',
      },
    },
    vehicleId:     { type: mongoose.Schema.Types.ObjectId, ref: 'Vehicle' },
    acceptedBidId: { type: mongoose.Schema.Types.ObjectId, ref: 'Bid' },
    finalCost:     { type: Number },
    review: {
      stars:     { type: Number, min: 1, max: 5 },
      tags:      { type: [String] },
      comment:   { type: String, maxlength: 300 },
      createdAt: { type: Date },
    },
  },
  { timestamps: true },
);

module.exports = mongoose.model('Job', jobSchema);
