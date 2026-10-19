const mongoose = require('mongoose');

const vehicleSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    make:      { type: String, trim: true, maxlength: 80 },
    model:     { type: String, trim: true, maxlength: 80 },
    year:      { type: Number, min: 1900, max: new Date().getUTCFullYear() + 1 },
    color:     { type: String, trim: true, maxlength: 80 },
    plate:     { type: String, required: true, trim: true, uppercase: true, maxlength: 30, match: /^[A-Z0-9 -]+$/ },
    isPrimary: { type: Boolean, default: false },
  },
  { timestamps: true },
);

vehicleSchema.index({ userId: 1 });

module.exports = mongoose.model('Vehicle', vehicleSchema);
