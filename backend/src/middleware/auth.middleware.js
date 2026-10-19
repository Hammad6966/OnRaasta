const { authenticateAccessToken } = require('../services/access.service');

/**
 * Extracts and verifies the Bearer token.
 * Attaches decoded payload to req.user on success.
 */
const verifyToken = async (req, res, next) => {
  try {
    const match = /^Bearer ([^\s]+)$/.exec(req.headers.authorization || '');
    if (!match) return res.status(401).json({ success: false, message: 'Access token required' });
    req.user = await authenticateAccessToken(match[1]);
    next();
  } catch (err) { next(err); }
};

/**
 * Role guard — use after verifyToken.
 * Usage: verifyRole('admin', 'mechanic')
 */
const verifyRole = (...roles) => (req, res, next) => {
  if (!req.user || !roles.includes(req.user.role)) {
    return res.status(403).json({ success: false, message: 'Insufficient permissions' });
  }
  next();
};

module.exports = { verifyToken, verifyRole };
