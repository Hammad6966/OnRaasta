const crypto = require('node:crypto');
const jwt = require('jsonwebtoken');
const mongoose = require('mongoose');
const Session = require('../models/RefreshSession');
const User = require('../models/User');
const { signAccessToken, idPattern, sameId } = require('./access.service');
const fail = require('../utils/http-error');
const WEEK = 7 * 24 * 60 * 60 * 1000;
const OVERLAP_MS = 3000;
const hash = token => crypto.createHash('sha256').update(token).digest('hex');
function refreshToken(user, sid) {
  return jwt.sign({ id: String(user._id), role: user.role, sid: String(sid),
    tokenUse: 'refresh', jti: crypto.randomBytes(32).toString('hex') }, process.env.JWT_REFRESH_SECRET,
  { algorithm: 'HS256', expiresIn: '7d' });
}
function decode(token, ignoreExpiration = false) {
  try {
    if (typeof token !== 'string' || token.length > 4096) throw new Error();
    const data = jwt.verify(token, process.env.JWT_REFRESH_SECRET, { algorithms: ['HS256'], ignoreExpiration });
    if (data.tokenUse !== 'refresh' || typeof data.id !== 'string' || typeof data.sid !== 'string' || typeof data.jti !== 'string' || !idPattern.test(data.id) || !idPattern.test(data.sid) ||
        !['user', 'mechanic'].includes(data.role) || !/^[a-f0-9]{64}$/.test(data.jti) || !Number.isInteger(data.exp)) throw new Error();
    return data;
  } catch { throw fail(401, 'Invalid or expired refresh session'); }
}
const publicUser = user => ({ id: String(user._id), name: user.name, phone: user.phone, role: user.role });
async function issue(user) {
  if (!user.isActive || !user.isVerified || !['user', 'mechanic'].includes(user.role)) throw fail(403, 'Mobile account not eligible');
  const sid = String(new mongoose.Types.ObjectId());
  const token = refreshToken(user, sid);
  await Session.create({ _id: sid, userId: user._id, role: user.role,
    tokenHash: hash(token), revokedAt: null, expiresAt: new Date(jwt.decode(token).exp * 1000) });
  return { accessToken: signAccessToken(user, sid), refreshToken: token, user: publicUser(user) };
}
async function rotate(token) {
  const data = decode(token), now = new Date(), tokenHash = hash(token);
  const user = await User.findById(data.id);
  if (!user || !user.isActive || !user.isVerified || user.role !== data.role) {
    await Session.findOneAndUpdate({ _id: data.sid, userId: data.id }, { $set: { revokedAt: now } });
    require('../socket/socket').revokeSession(data.sid);
    throw fail(user ? 403 : 401, 'Refresh account is no longer eligible');
  }
  const next = refreshToken(user, data.sid);
  const session = await Session.findOneAndUpdate({ _id: data.sid, userId: data.id, role: data.role,
    tokenHash, revokedAt: null, expiresAt: { $gt: now } },
  { $set: { tokenHash: hash(next), previousHash: tokenHash, rotatedAt: now,
    expiresAt: new Date(jwt.decode(next).exp * 1000) } }, { new: true });
  if (session) return { accessToken: signAccessToken(user, data.sid), refreshToken: next, user: publicUser(user) };
  const current = await Session.findById(data.sid).select('+tokenHash +previousHash');
  if (current && sameId(current.userId, data.id) && !current.revokedAt && new Date(current.expiresAt) > now) {
    // A brief overlap rejects a simultaneous duplicate without revoking the
    // successful request's session. No token/credential is returned to a loser.
    if (current.previousHash === tokenHash && now - new Date(current.rotatedAt) <= OVERLAP_MS) {
      throw fail(409, 'Refresh already rotated; sign in if current credentials are unavailable');
    }
    await Session.findOneAndUpdate({ _id: data.sid, userId: data.id, revokedAt: null }, { $set: { revokedAt: now } });
  }
  require('../socket/socket').revokeSession(data.sid);
  throw fail(401, 'Refresh session revoked or reused');
}
async function revoke(token) {
  const data = decode(token, true);
  await Session.findOneAndUpdate({ _id: data.sid, userId: data.id }, { $set: { revokedAt: new Date() } });
  require('../socket/socket').revokeSession(data.sid);
}
module.exports = { issue, rotate, revoke, decode, hash, publicUser, WEEK, OVERLAP_MS };
