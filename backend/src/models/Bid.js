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
    labourCost: { type: Number, required: true, min: 500 },
    partsCost:  { type: Number, default: 0 },
    totalCost:  { type: Number, required: true },
    eta:        { type: Number, required: true },  // minutes
    status: {
      type: String,
      enum: ['pending', 'accepted', 'declined', 'expired'],
      default: 'pending',
    },
  },
  { timestamps: true },
);

module.exports = mongoose.model('Bid', bidSchema);
