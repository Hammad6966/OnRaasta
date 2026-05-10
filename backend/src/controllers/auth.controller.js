const bcrypt = require('bcryptjs');
const jwt    = require('jsonwebtoken');
const User   = require('../models/User');
const { sendOtp, verifyOtp: verifyOtpService } = require('../services/twilio.service');

// ── Helpers ──────────────────────────────────────────────────────────────────

const generateTokens = (user) => ({
  accessToken: jwt.sign(
    { id: user._id, role: user.role },
    process.env.JWT_SECRET,
    { expiresIn: '15m' },
  ),
  refreshToken: jwt.sign(
    { id: user._id, role: user.role },
    process.env.JWT_REFRESH_SECRET,
    { expiresIn: '7d' },
  ),
});

const userPayload = (user) => ({
  id:    user._id,
  name:  user.name,
  phone: user.phone,
  role:  user.role,
});

// ── Controllers ───────────────────────────────────────────────────────────────

/**
 * POST /api/auth/register
 * Creates (or updates unverified) user and sends OTP.
 */
const register = async (req, res, next) => {
  try {
    console.log('register body:', req.body);

    const existing = await User.findOne({ phone: req.body.phone });
    console.log('Existing user found:', existing);

    if (existing && existing.isVerified === true) {
      return res.status(409).json({ success: false, message: 'Phone already registered. Please login.' });
    }

    if (existing && existing.isVerified === false) {
      existing.name         = req.body.name;
      existing.passwordHash = await bcrypt.hash(req.body.password, 12);
      await existing.save();
      await sendOtp(req.body.phone);
      return res.status(201).json({ success: true, message: 'OTP resent' });
    }

    // No existing user — create fresh
    const passwordHash = await bcrypt.hash(req.body.password, 12);
    await User.create({ name: req.body.name, phone: req.body.phone, passwordHash });
    await sendOtp(req.body.phone);
    return res.status(201).json({ success: true, message: 'OTP sent' });
  } catch (err) {
    next(err);
  }
};

/**
 * POST /api/auth/verify-otp
 * Verifies OTP, marks user verified, returns tokens.
 */
const verifyOtp = async (req, res, next) => {
  try {
    console.log('verifyOtp body:', req.body);
    const { phone, otp, code } = req.body;
    const otpCode = otp || code;
    console.log('phone:', phone, 'otpCode:', otpCode, 'DEV_OTP:', process.env.DEV_OTP);

    const user = await User.findOne({ phone });
    if (!user) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    const result = await verifyOtpService(phone, otpCode);
    if (result.status !== 'approved') {
      return res.status(400).json({ success: false, message: 'Invalid or expired OTP' });
    }

    user.isVerified = true;
    await user.save();

    const { accessToken, refreshToken } = generateTokens(user);

    return res.status(200).json({
      success: true,
      accessToken,
      refreshToken,
      user: userPayload(user),
    });
  } catch (err) {
    next(err);
  }
};

/**
 * POST /api/auth/login
 * Authenticates with phone + password, enforces lockout after 5 failures.
 */
const login = async (req, res, next) => {
  try {
    const { phone, password } = req.body;

    const user = await User.findOne({ phone, isVerified: true });
    if (!user) {
      return res.status(404).json({ success: false, message: 'Account not found' });
    }

    if (!user.isActive) {
      return res.status(403).json({ success: false, message: 'Account has been deactivated' });
    }

    if (user.lockoutUntil && user.lockoutUntil > Date.now()) {
      return res.status(429).json({ success: false, message: 'Account temporarily locked. Try again later.' });
    }

    const match = await bcrypt.compare(password, user.passwordHash);
    if (!match) {
      user.failedLoginAttempts += 1;
      if (user.failedLoginAttempts >= 5) {
        user.lockoutUntil = new Date(Date.now() + 30 * 60 * 1000); // 30 min
      }
      await user.save();
      return res.status(401).json({ success: false, message: 'Invalid credentials' });
    }

    // Success — reset failure counters
    user.failedLoginAttempts = 0;
    user.lockoutUntil = undefined;
    await user.save();

    const { accessToken, refreshToken } = generateTokens(user);

    return res.status(200).json({
      success: true,
      accessToken,
      refreshToken,
      user: userPayload(user),
    });
  } catch (err) {
    next(err);
  }
};

/**
 * POST /api/auth/refresh
 * Issues a new accessToken from a valid refreshToken.
 */
const refresh = async (req, res, next) => {
  try {
    const { refreshToken } = req.body;
    if (!refreshToken) {
      return res.status(400).json({ success: false, message: 'Refresh token required' });
    }

    const decoded = jwt.verify(refreshToken, process.env.JWT_REFRESH_SECRET);
    const user    = await User.findById(decoded.id);
    if (!user) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    const accessToken = jwt.sign(
      { id: user._id, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: '15m' },
    );

    return res.status(200).json({ success: true, accessToken });
  } catch (err) {
    next(err);
  }
};

/**
 * POST /api/auth/resend-otp
 * Re-sends OTP to a registered (unverified) phone number.
 */
const resendOtp = async (req, res, next) => {
  try {
    const { phone } = req.body;
    const user = await User.findOne({ phone });
    if (!user) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }
    await sendOtp(phone);
    return res.status(200).json({ success: true, message: `OTP resent to +92${phone}` });
  } catch (err) {
    next(err);
  }
};

module.exports = { register, verifyOtp, login, refresh, resendOtp };
