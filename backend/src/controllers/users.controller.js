const mongoose = require('mongoose');
const User = require('../models/User');
const Vehicle = require('../models/Vehicle');
const Job = require('../models/Job');
const fail = require('../utils/http-error');
const fields = 'name email phone role isVerified createdAt vehicleIds emergencyContacts photo';
exports.getProfile = async (req, res, next) => {
  try { const user = await User.findById(req.user.id).select(fields);
    if (!user) throw fail(404, 'Account not found');
    const statistics = req.user.role === 'user' ? await require('../services/history.service').summary({ userId: req.user.id }) : undefined;
    res.json({ success: true, data: { ...(typeof user.toObject === 'function' ? user.toObject() : user), ...(statistics ? { statistics } : {}) } });
  } catch (e) { next(e); }
};
exports.updateProfile = async (req, res, next) => {
  try {
    const patch = {};
    if (req.body.name !== undefined) patch.name = req.body.name.trim();
    if (req.body.email !== undefined) {
      patch.email = req.body.email.trim().toLowerCase();
      const other = await User.findOne({ email: patch.email, _id: { $ne: req.user.id } });
      if (other) throw fail(409, 'Email is already in use');
    }
    if (req.body.emergencyContacts !== undefined && req.user.role !== 'user') throw fail(403, 'Driver access required for emergency contacts');
    if (req.body.emergencyContacts !== undefined) patch.emergencyContacts = req.body.emergencyContacts.map(c => ({ name: c.name.trim(), phone: c.phone }));
    const user = await User.findByIdAndUpdate(req.user.id, { $set: patch }, { new: true, runValidators: true }).select(fields);
    if (!user) throw fail(404, 'Account not found');
    res.json({ success: true, data: user });
  } catch (e) { next(e); }
};
// Serialize vehicle mutations and referenced-job creation on the owning User.
exports.withVehicles = async (userId, work) => {
  const session = await mongoose.startSession();
  try { let result;
    await session.withTransaction(async () => {
      const owner = await User.findOneAndUpdate({ _id: userId }, { $inc: { __v: 1 } }, { new: true, session });
      if (!owner) throw fail(404, 'Account not found');
      result = await work(session, owner);
    }); return result;
  } finally { await session.endSession(); }
};
exports.listVehicles = async (req, res, next) => {
  try { res.json({ success: true, data: await Vehicle.find({ userId: req.user.id }).sort({ createdAt: 1 }) }); }
  catch (e) { next(e); }
};
exports.saveVehicle = async (req, res, next) => {
  try {
    const saved = await exports.withVehicles(req.user.id, async (session, owner) => {
      const vehicles = await Vehicle.find({ userId: req.user.id }).session(session);
      let vehicle = req.params.id ? vehicles.find(v => String(v._id) === req.params.id) : null;
      if (req.params.id && !vehicle) throw fail(404, 'Vehicle not found');
      const patch = {};
      for (const k of ['make', 'model', 'year', 'color', 'plate']) if (req.body[k] !== undefined) patch[k] = typeof req.body[k] === 'string' ? req.body[k].trim() : req.body[k];
      if (patch.plate) patch.plate = patch.plate.toUpperCase();
      const primary = req.body.isPrimary === true || !vehicles.some(v => v.isPrimary) || vehicle?.isPrimary === true;
      if (req.body.isPrimary === false && vehicle?.isPrimary) throw fail(409, 'Select another primary vehicle first');
      if (primary) await Vehicle.updateMany({ userId: req.user.id }, { $set: { isPrimary: false } }, { session });
      if (vehicle) vehicle = await Vehicle.findOneAndUpdate({ _id: vehicle._id, userId: req.user.id }, { $set: { ...patch, isPrimary: primary } }, { new: true, runValidators: true, session });
      else [vehicle] = await Vehicle.create([{ ...patch, userId: req.user.id, isPrimary: primary }], { session });
      owner.vehicleIds = [...vehicles.filter(v => String(v._id) !== String(vehicle._id)).map(v => v._id), vehicle._id];
      await owner.save({ session }); return vehicle;
    });
    res.status(req.params.id ? 200 : 201).json({ success: true, data: saved });
  } catch (e) { next(e); }
};
exports.deleteVehicle = async (req, res, next) => {
  try {
    await exports.withVehicles(req.user.id, async (session, owner) => {
      const vehicle = await Vehicle.findOne({ _id: req.params.id, userId: req.user.id }).session(session);
      if (!vehicle) throw fail(404, 'Vehicle not found');
      if (await Job.exists({ vehicleId: vehicle._id }).session(session)) throw fail(409, 'Vehicle is referenced by a job and cannot be deleted');
      await Vehicle.deleteOne({ _id: vehicle._id, userId: req.user.id }, { session });
      const remaining = await Vehicle.find({ userId: req.user.id }).session(session);
      if (vehicle.isPrimary && remaining.length) await Vehicle.findByIdAndUpdate(remaining[0]._id, { $set: { isPrimary: true } }, { session });
      owner.vehicleIds = remaining.map(v => v._id); await owner.save({ session });
    });
    res.json({ success: true, data: { deleted: true } });
  } catch (e) { next(e); }
};
