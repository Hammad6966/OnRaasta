const mongoose = require('mongoose');

const userSchema = new mongoose.Schema(
  {
    name: {
      type: String,
      required: true,
      trim: true,
      minlength: 2,
    },
    email: {
      type:      String,
      trim:      true,
      lowercase: true,
      sparse:    true,
      default:   undefined,
    },
    phone: {
      type: String,
      required: true,
      unique: true,
      trim: true,
    },
    passwordHash: {
      type: String,
      required: true,
    },
    role: {
      type: String,
      enum: ['user', 'mechanic', 'admin'],
      default: 'user',
    },
    isVerified: { type: Boolean, default: false },
    isActive:   { type: Boolean, default: true  },
    vehicleIds: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Vehicle' }],
    emergencyContacts: [
      {
        name:  { type: String },
        phone: { type: String },
      },
    ],
    failedLoginAttempts: { type: Number, default: 0 },
    lockoutUntil:        { type: Date },
  },
  { timestamps: true },
);

module.exports = mongoose.model('User', userSchema);
