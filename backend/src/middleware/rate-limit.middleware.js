const rateLimit = require('express-rate-limit');
const limiter = (max) => rateLimit({
  windowMs: 15 * 60 * 1000, max, standardHeaders: true, legacyHeaders: false,
  message: { success: false, message: 'Too many requests. Please try again later.' },
});
module.exports = { authLimiter: limiter(10), apiLimiter: limiter(100) };
