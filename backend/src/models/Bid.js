const mongoose = require('mongoose');

const bidSchema = new mongoose.Schema(
  {
    jobId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Job',
      required: true,
    },
    mechanicId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Mechanic',
      required: true,
    },
    labourCost: { type: Number, required: true, min: 500, max: 1e8 },
    partsCost:  { type: Number, default: 0, min: 0, max: 1e8 },
    totalCost:  { type: Number, required: true, min: 500, max: 2e8 },
    eta:        { type: Number, required: true, min: 1, max: 1440, validate: Number.isInteger },
    status: {
      type: String,
      enum: ['pending', 'accepted', 'declined', 'expired'],
      default: 'pending',
    },
  },
  { timestamps: true },
);

bidSchema.index({ jobId: 1, mechanicId: 1 }, {
  name: 'one_pending_bid_per_mechanic', unique: true, partialFilterExpression: { status: 'pending' },
});
bidSchema.index({ jobId: 1 }, {
  name: 'one_accepted_bid_per_job', unique: true, partialFilterExpression: { status: 'accepted' },
});

module.exports = mongoose.model('Bid', bidSchema);
