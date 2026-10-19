const mongoose = require('mongoose');

const amount = { type: Number, min: 0, max: Number.MAX_SAFE_INTEGER, validate: Number.isSafeInteger };
const priceFields = { currency: { type: String, enum: ['PKR'] }, version: Number,
  acceptedBidId: { type: mongoose.Schema.Types.ObjectId, ref: 'Bid' },
  labourMinor: amount, partsMinor: amount, totalMinor: amount };
const agreedSchema = new mongoose.Schema(priceFields, { _id: false });
const accountingSchema = new mongoose.Schema({ ...priceFields, commissionBps: { type: Number, enum: [1500] },
  commissionMinor: amount, netMinor: amount, recordedAt: Date }, { _id: false });
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
    finalCost:     { type: Number }, // Legacy optional field, not a confirmed adjustment.
    agreedPricing: { type: agreedSchema, default: undefined },
    accounting: { type: accountingSchema, default: undefined },
    statusVersion: { type: Number, default: 0, min: 0 },
    statusChangedAt: { type: Date },
    enRouteAt: { type: Date },
    arrivedAt: { type: Date },
    startedAt: { type: Date },
    completedAt: { type: Date },
    cancelledAt: { type: Date },
    latestMechanicLocation: { type: new mongoose.Schema({
      mechanicId: {type:mongoose.Schema.Types.ObjectId,ref:'Mechanic'},
      acceptedBidId: {type:mongoose.Schema.Types.ObjectId,ref:'Bid'},
      lat:Number, lng:Number, accuracy:Number,
      observedAt:Date, receivedAt:Date, expiresAt:Date,
    }, {_id:false}), select:false, default:undefined },
    review: {
      stars:     { type: Number, min: 1, max: 5, validate: Number.isInteger },
      tags:      { type: [String], enum: require('../utils/review-policy').tags,
        validate: v => v.length <= 3 && new Set(v).size === v.length },
      comment:   { type: String, maxlength: 300 },
      createdAt: { type: Date },
    },
  },
  { timestamps: true },
);

jobSchema.index({ userId: 1, createdAt: -1, _id: -1 });
jobSchema.index({ mechanicId: 1, status: 1, completedAt: -1 });
module.exports = mongoose.model('Job', jobSchema);
