const { body, param, query } = require('express-validator');
const { validateRequest } = require('./validation.middleware');
const { idPattern } = require('../services/access.service');
const object = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const finite = (v, min, max) => typeof v === 'number' && Number.isFinite(v) && v >= min && v <= max;
const money = (v, min, max) => finite(v, min, max) && /^\d+(?:\.\d{1,2})?$/.test(String(v));
const text = (v, min, max) => typeof v === 'string' && v.trim().length >= min && v.length <= max;
const only = (v, keys) => object(v) && Object.keys(v).every(k => keys.includes(k));
const coordinates = (v) => object(v) && finite(v.lat, -90, 90) && finite(v.lng, -180, 180);
const faults = ['flat_tire', 'dead_battery', 'engine_overheating', 'oil_leak', 'brake_failure',
  'transmission_issue', 'electrical_fault', 'fuel_problem', 'ac_fault', 'suspension_issue', 'coolant_leak', 'unknown'];
const states = ['pending', 'bidding', 'accepted', 'en_route', 'arrived', 'in_progress', 'completed', 'cancelled'];
function diagnosis(v) {
  if (v == null) return true;
  return only(v, ['fault_class', 'confidence', 'cost_min', 'cost_max', 'skill_required']) &&
    faults.includes(v.fault_class) && finite(v.confidence, 0, 1) &&
    finite(v.cost_min, 0, 1e8) && finite(v.cost_max, v.cost_min, 1e8) && text(v.skill_required, 1, 100);
}
function photoUrl(v) {
  if (!text(v, 1, 2048)) return false;
  try { const u = new URL(v); return ['http:', 'https:'].includes(u.protocol) && !u.username && !u.password; }
  catch { return false; }
}
const check = (predicate, message) => [body().custom(v => {
  if (!predicate(v)) throw new Error(message);
  return true;
}), validateRequest];
const phone = v => typeof v === 'string' && /^\d{10}$/.test(v);
const password = v => text(v, 8, 128);
const vehicle = (v, create) => only(v, ['make', 'model', 'year', 'color', 'plate', 'isPrimary']) && Object.keys(v).length > 0 &&
  (!create || ['make', 'model', 'plate'].every(k => v[k] !== undefined)) &&
  ['make', 'model', 'color'].every(k => v[k] === undefined || text(v[k], 1, 80)) &&
  (v.plate === undefined || text(v.plate, 2, 30) && /^[A-Za-z0-9 -]+$/.test(v.plate)) &&
  (v.year === undefined || Number.isInteger(v.year) && finite(v.year, 1900, new Date().getUTCFullYear() + 1)) &&
  (v.isPrimary === undefined || typeof v.isPrimary === 'boolean');
module.exports = {
  vehicleCreate: check(v => vehicle(v, true), 'Invalid vehicle details'),
  vehicleUpdate: check(v => vehicle(v, false), 'Invalid vehicle details'),
  mechanicProfile: check(v => only(v, ['name', 'skills', 'shopAddress', 'serviceRadius']) && (v.name === undefined || text(v.name, 2, 100)) && Object.keys(v).length > 0 &&
    (v.skills === undefined || Array.isArray(v.skills) && v.skills.length <= 16 && new Set(v.skills).size === v.skills.length && v.skills.every(s => require('../utils/profile-policy').skills.includes(s))) &&
    (v.shopAddress === undefined || text(v.shopAddress, 0, 500)) &&
    (v.serviceRadius === undefined || finite(v.serviceRadius, 1, 100)), 'Invalid mechanic profile'),
  object, coordinates, states,
  id: [param('id').isMongoId(), validateRequest],
  mechanicId: [param('mechanicId').isMongoId(), validateRequest],
  bidQuery: [query('jobId').isMongoId(), validateRequest],
  nearby: [query().custom(v => {
    if (!only(v, ['lat', 'lng']) || typeof v.lat !== 'string' || typeof v.lng !== 'string' ||
        !v.lat.trim() || !v.lng.trim() || !coordinates({ lat: Number(v.lat), lng: Number(v.lng) })) {
      throw new Error('Invalid coordinates');
    }
    return true;
  }), validateRequest],
  register: check(v => only(v, ['name', 'email', 'phone', 'password', 'role']) &&
    text(v.name, 2, 100) && phone(v.phone) && password(v.password) &&
    (v.email === undefined || text(v.email, 3, 254) && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v.email)) &&
    (v.role === undefined || ['user', 'mechanic'].includes(v.role)), 'Invalid registration details or role'),
  login: check(v => only(v, ['phone', 'password']) && phone(v.phone) && text(v.password, 1, 128), 'Invalid login details'),
  otp: check(v => only(v, ['phone', 'otp', 'code']) && phone(v.phone) &&
    typeof (v.otp || v.code) === 'string' && /^\d{4,8}$/.test(v.otp || v.code), 'Invalid OTP request'),
  resend: check(v => only(v, ['phone']) && phone(v.phone), 'Invalid phone'),
  refresh: check(v => only(v, ['refreshToken']) && text(v.refreshToken, 1, 4096), 'Invalid refresh request'),
  adminLogin: check(v => only(v, ['email', 'password']) && text(v.email, 3, 254) &&
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v.email) && text(v.password, 1, 128), 'Invalid login details'),
  job: check(v => only(v, ['description', 'location', 'aiDiagnosis', 'photos', 'vehicleId']) &&
    text(v.description, 1, 2000) && only(v.location, ['lat', 'lng', 'address']) && coordinates(v.location) &&
    (v.location.address === undefined || text(v.location.address, 0, 500)) && diagnosis(v.aiDiagnosis) &&
    (v.photos === undefined || Array.isArray(v.photos) && v.photos.length <= 3 && v.photos.every(photoUrl)) &&
    (v.vehicleId === undefined || typeof v.vehicleId === 'string' && idPattern.test(v.vehicleId)), 'Invalid breakdown request'),
  bid: check(v => only(v, ['jobId', 'mechanicId', 'labourCost', 'partsCost', 'totalCost', 'eta']) &&
    typeof v.jobId === 'string' && idPattern.test(v.jobId) &&
    (v.mechanicId === undefined || typeof v.mechanicId === 'string' && idPattern.test(v.mechanicId)) &&
    money(v.labourCost, 500, 1e8) && money(v.partsCost ?? 0, 0, 1e8) &&
    money(v.totalCost, 500, 2e8) && Number.isInteger(v.eta) && finite(v.eta, 1, 1440) &&
    Math.round(v.totalCost * 100) === Math.round(v.labourCost * 100) + Math.round((v.partsCost ?? 0) * 100),
  'Invalid costs or ETA; labour must be at least PKR 500 and total must match components'),
  status: check(v => only(v, ['status', 'expectedStatus', 'expectedVersion']) && states.includes(v.status) &&
    (v.expectedStatus === undefined || states.includes(v.expectedStatus)) &&
    (v.expectedVersion === undefined || Number.isSafeInteger(v.expectedVersion) && v.expectedVersion >= 0), 'Invalid job status'),
  accept: check(v => v === undefined || only(v, []) || v === null, 'Acceptance does not accept assignment fields'),
  review: check(v => only(v, ['stars', 'tags', 'comment']) && Number.isInteger(v.stars) && finite(v.stars, 1, 5) &&
    (v.comment === undefined || text(v.comment, 0, 300)) &&
    (v.tags === undefined || Array.isArray(v.tags) && v.tags.length <= 3 && new Set(v.tags).size === v.tags.length && v.tags.every(t => require('../utils/review-policy').tags.includes(t))), 'Invalid review'),
  verification: check(v => only(v, ['status', 'rejectionReason']) && ['verified', 'rejected'].includes(v.status) &&
    (v.rejectionReason === undefined || text(v.rejectionReason, 0, 500)), 'Invalid verification decision'),
  profile: check(v => only(v, ['name', 'email', 'emergencyContacts']) &&
    (v.name === undefined || text(v.name, 2, 100)) &&
    (v.email === undefined || text(v.email, 3, 254) && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v.email)) &&
    (v.emergencyContacts === undefined || Array.isArray(v.emergencyContacts) && v.emergencyContacts.length <= 5 && new Set(v.emergencyContacts.map(c => c?.phone)).size === v.emergencyContacts.length &&
      v.emergencyContacts.every(c => only(c, ['name', 'phone']) && text(c.name, 1, 100) &&
        typeof c.phone === 'string' && /^\+?\d{10,15}$/.test(c.phone))), 'Invalid profile'),
};
