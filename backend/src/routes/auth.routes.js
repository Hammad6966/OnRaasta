const express    = require('express');
const rateLimit  = require('express-rate-limit');
const { body }   = require('express-validator');

const { register, verifyOtp, login, refresh, resendOtp } = require('../controllers/auth.controller');
const { validateRequest } = require('../middleware/validation.middleware');

const router = express.Router();

// 10 requests per 15 minutes on all auth routes
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'Too many requests — please try again later' },
});

router.use(authLimiter);

router.post(
  '/register',
  [
    body('name').notEmpty().withMessage('Name is required'),
    body('phone')
      .isLength({ min: 10, max: 10 })
      .isNumeric()
      .withMessage('Phone must be exactly 10 digits'),
    body('password')
      .isLength({ min: 8 })
      .withMessage('Password must be at least 8 characters'),
    validateRequest,
  ],
  register,
);

router.post('/verify-otp', verifyOtp);
router.post('/login',      login);
router.post('/refresh',    refresh);
router.post('/resend-otp', resendOtp);

module.exports = router;
