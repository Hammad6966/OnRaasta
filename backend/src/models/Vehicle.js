const mongoose = require('mongoose');

const vehicleSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    make:      { type: String },
    model:     { type: String },
    year:      { type: Number },
    color:     { type: String },
    plate:     { type: String, required: true },
    isPrimary: { type: Boolean, default: false },
  },
  { timestamps: true },
);

module.exports = mongoose.model('Vehicle', vehicleSchema);
