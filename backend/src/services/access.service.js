const jwt = require('jsonwebtoken');
const User = require('../models/User');
const Mechanic = require('../models/Mechanic');
const fail = require('../utils/http-error');
const idPattern = /^[a-f\d]{24}$/i;
const sameId = (a, b) => a != null && b != null && String(a) === String(b);

async function authenticateAccessToken(token) {
  let decoded;
  try {
    if (typeof token !== 'string' || !token || token.length > 4096) throw new Error();
    decoded = jwt.verify(token, process.env.JWT_SECRET, { algorithms: ['HS256'] });
    if (decoded.tokenUse !== 'access' || typeof decoded.id !== 'string' ||
        !idPattern.test(decoded.id) || !['user', 'mechanic', 'admin'].includes(decoded.role) || !Number.isInteger(decoded.exp)) throw new Error();
  } catch (error) {
    const rejected = fail(401, 'Invalid or expired access token');
    if (error.name === 'TokenExpiredError') rejected.publicCode = 'ACCESS_TOKEN_EXPIRED';
    throw rejected;
  }
  const user = await User.findById(decoded.id).select('name role isActive isVerified');
  if (!user) throw fail(401, 'Account no longer exists');
  if (!user.isActive || !user.isVerified) { const err = fail(403, 'Account is inactive or unverified'); err.publicCode = 'ACCOUNT_UNAVAILABLE'; throw err; }
  if (decoded.role !== user.role || !['user', 'mechanic', 'admin'].includes(user.role)) { const err = fail(403, 'Invalid account role'); err.publicCode = 'ACCOUNT_UNAVAILABLE'; throw err; }
  if (decoded.sid !== undefined) {
    if (typeof decoded.sid !== 'string' || !idPattern.test(decoded.sid) || !await require('../models/RefreshSession').exists({ _id: decoded.sid, userId: user._id, role: user.role, revokedAt: null, expiresAt: { $gt: new Date() } })) throw fail(401, 'Session revoked or expired');
  }
  return { id: String(user._id), role: user.role, name: user.name, exp: decoded.exp, ...(decoded.sid ? { sid: decoded.sid } : {}) };
}
async function approvedMechanic(user, session) {
  if (user.role !== 'mechanic') throw fail(403, 'Approved mechanic access required');
  // Serialize in-flight privileged mutations with administrative suspension.
  const accountFilter = { _id: user.id, role: 'mechanic', isActive: true, isVerified: true };
  const account = session
    ? await User.findOneAndUpdate(accountFilter, { $inc: { __v: 1 } }, { new: true, session })
    : await User.exists(accountFilter);
  if (!account) throw fail(403, 'Account is inactive or unverified');
  const filter = { userId: user.id, isApproved: true };
  // A transactional write also conflicts with concurrent administrative revocation.
  const mechanic = await (session
    ? Mechanic.findOneAndUpdate(filter, { $inc: { __v: 1 } }, { new: true, session })
    : Mechanic.findOne(filter));
  if (!mechanic) throw fail(403, 'Approved mechanic access required');
  return mechanic;
}
async function canViewJob(user, job) {
  if (user.role === 'admin' || sameId(job.userId, user.id)) return true;
  if (user.role !== 'mechanic' || !job.mechanicId) return false;
  return !!await Mechanic.exists({ _id: job.mechanicId, userId: user.id, isApproved: true });
}
function signAccessToken(user, sid) {
  return jwt.sign({ id: String(user._id), role: user.role, tokenUse: 'access', ...(sid ? { sid: String(sid) } : {}) },
    process.env.JWT_SECRET, { algorithm: 'HS256', expiresIn: '15m' });
}
module.exports = { authenticateAccessToken, approvedMechanic, canViewJob, sameId, idPattern, signAccessToken };
