const { authenticateAccessToken, approvedMechanic, sameId } = require('./access.service');
const { coordinates } = require('../middleware/request-validation');
const fail = require('../utils/http-error');

// Process-local authority. Never persist isOnline=true: it outlives connections
// and process crashes. Discovery and dispatch always consult this registry.
const entries = new Map(); // mechanic profile ID -> one acknowledged session
const LEASE_MS = 90000;
const validCoordinates = value => coordinates(value) && !(value.lat === 0 && value.lng === 0);
function radius(mechanic) {
  const value = mechanic.serviceRadius ?? 15;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 1 || value > 100) {
    throw fail(409, 'Configured service radius must be between 1 and 100 km');
  }
  return value;
}
function haversine(lat1, lng1, lat2, lng2) {
  const rad = value => value * Math.PI / 180;
  const a = Math.sin(rad(lat2 - lat1) / 2) ** 2 + Math.cos(rad(lat1)) *
    Math.cos(rad(lat2)) * Math.sin(rad(lng2 - lng1) / 2) ** 2;
  const bounded = Math.max(0, Math.min(1, a));
  return 6371 * 2 * Math.atan2(Math.sqrt(bounded), Math.sqrt(1 - bounded));
}
function snapshot(entry) {
  return { mechanicId: entry.mechanicId, isOnline: true, lat: entry.lat, lng: entry.lng,
    serviceRadius: entry.serviceRadius };
}
function remove(entry, reason) {
  if (entries.get(entry.mechanicId) !== entry) return;
  entries.delete(entry.mechanicId);
  entry.socket.leave(`mechanic_${entry.mechanicId}`);
  if (reason) entry.socket.emit('mechanic:availability', { isOnline: false, reason });
}
function disconnect(socketId) {
  for (const entry of entries.values()) if (entry.socket.id === socketId) remove(entry);
}
function revoke(mechanicId) {
  const entry = entries.get(String(mechanicId));
  if (entry) remove(entry, 'Approval or account eligibility changed');
}
function checkIdentity(data, mechanic) {
  if (data?.mechanicId !== undefined && !sameId(data.mechanicId, mechanic._id)) {
    throw fail(403, 'Mechanic identity mismatch');
  }
}
async function online(socket, user, data) {
  const mechanic = await approvedMechanic(user);
  checkIdentity(data, mechanic);
  if (!validCoordinates(data)) throw fail(400, 'Valid current GPS coordinates are required');
  const serviceRadius = radius(mechanic);
  if (data.serviceRadius !== undefined && (typeof data.serviceRadius !== 'number' ||
      data.serviceRadius < 1 || data.serviceRadius > 100 || data.serviceRadius !== serviceRadius)) {
    throw fail(400, 'Use the configured mechanic service radius');
  }
  if (!socket.connected) throw fail(409, 'Socket disconnected before presence registration');
  const mechanicId = String(mechanic._id);
  const previous = entries.get(mechanicId);
  if (previous && previous.socket.id !== socket.id) remove(previous, 'Another session replaced this availability session');
  const entry = { mechanicId, userId: user.id, socket, token: socket.handshake.auth.token,
    lat: data.lat, lng: data.lng, serviceRadius, updatedAt: Date.now() };
  entries.set(mechanicId, entry);
  await socket.join(`mechanic_${mechanicId}`);
  if (!current(entry)) throw fail(409, 'Availability session changed');
  return snapshot(entry);
}
async function offline(socket, user, data) {
  if (user.role !== 'mechanic') throw fail(403, 'Mechanic access required');
  // Approval is intentionally not required to leave availability.
  const Mechanic = require('../models/Mechanic');
  const mechanic = await Mechanic.findOne({ userId: user.id });
  if (!mechanic) throw fail(404, 'Mechanic profile not found');
  checkIdentity(data, mechanic);
  const entry = entries.get(String(mechanic._id));
  if (entry && entry.socket.id !== socket.id) throw fail(409, 'This availability session was replaced');
  if (entry) remove(entry);
  return { mechanicId: String(mechanic._id), isOnline: false };
}
async function update(socket, user, data) {
  const mechanic = await approvedMechanic(user);
  checkIdentity(data, mechanic);
  if (!validCoordinates(data)) throw fail(400, 'Valid current GPS coordinates are required');
  const entry = entries.get(String(mechanic._id));
  if (!entry || entry.socket.id !== socket.id) throw fail(409, 'Mechanic is offline or session was replaced');
  entry.lat = data.lat; entry.lng = data.lng;
  entry.serviceRadius = radius(mechanic); entry.updatedAt = Date.now();
  return snapshot(entry);
}
async function eligibleEntries() {
  const eligible = [];
  for (const entry of [...entries.values()]) {
    try {
      if (!entry.socket.connected || Date.now() - entry.updatedAt >= LEASE_MS) throw fail(409, 'Presence expired');
      const user = await authenticateAccessToken(entry.token);
      const mechanic = await approvedMechanic(user);
      if (!sameId(mechanic._id, entry.mechanicId)) throw fail(403, 'Invalid presence');
      entry.serviceRadius = radius(mechanic);
      if (entries.get(entry.mechanicId) === entry) eligible.push({ entry, mechanic, user });
    } catch { remove(entry, 'Availability expired or account is no longer eligible'); }
  }
  return eligible;
}
async function nearby(lat, lng) {
  if (!validCoordinates({ lat, lng })) throw fail(400, 'Invalid coordinates');
  const result = [];
  for (const item of await eligibleEntries()) {
    const distance = haversine(lat, lng, item.entry.lat, item.entry.lng);
    if (distance <= item.entry.serviceRadius) result.push({ ...item, distance });
  }
  return result.sort((a, b) => a.distance - b.distance);
}
function current(entry) { return entries.get(entry.mechanicId) === entry && entry.socket.connected; }
function isOnline(mechanicId) {
  const entry = entries.get(String(mechanicId));
  return !!entry && current(entry) && Date.now() - entry.updatedAt < LEASE_MS;
}
function clear() { entries.clear(); }
module.exports = { online, offline, update, disconnect, revoke, nearby, current, isOnline,
  eligibleEntries, clear, haversine, validCoordinates, LEASE_MS };
