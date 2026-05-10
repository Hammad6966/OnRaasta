const twilio = require('twilio');

const getClient = () => twilio(
  process.env.TWILIO_ACCOUNT_SID,
  process.env.TWILIO_AUTH_TOKEN,
);

/**
 * Send OTP via Twilio Verify to a Pakistani number.
 * @param {string} phone - 10-digit local number, e.g. "3001234567"
 */
const sendOtp = async (phone) => {
  return getClient().verify.v2
    .services(process.env.TWILIO_VERIFY_SERVICE_SID)
    .verifications.create({ to: `+92${phone}`, channel: 'sms' });
};

/**
 * Verify OTP code.
 * In development, accepts DEV_OTP from .env without hitting Twilio.
 * @param {string} phone - 10-digit local number
 * @param {string} code  - OTP entered by user
 * @returns {{ status: 'approved' | 'pending' }}
 */
const verifyOtp = async (phone, code) => {
  if (process.env.NODE_ENV === 'development' && code === process.env.DEV_OTP) {
    return { status: 'approved' };
  }
  return getClient().verify.v2
    .services(process.env.TWILIO_VERIFY_SERVICE_SID)
    .verificationChecks.create({ to: `+92${phone}`, code });
};

module.exports = { sendOtp, verifyOtp };
