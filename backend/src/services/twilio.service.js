const twilio = require('twilio');

const getClient = () => twilio(
  process.env.TWILIO_ACCOUNT_SID,
  process.env.TWILIO_AUTH_TOKEN,
);

const sendOtp = async (phone) => {
  if (process.env.NODE_ENV === 'development') {
    return { status: 'pending' };
  }
  return getClient().verify.v2
    .services(process.env.TWILIO_VERIFY_SERVICE_SID)
    .verifications.create({ to: `+92${phone}`, channel: 'sms' });
};

const verifyOtp = async (phone, code) => {
  if (process.env.NODE_ENV === 'development') {
    return { status: typeof code === 'string' && !!process.env.DEV_OTP &&
      code === process.env.DEV_OTP ? 'approved' : 'rejected' };
  }
  return getClient().verify.v2
    .services(process.env.TWILIO_VERIFY_SERVICE_SID)
    .verificationChecks.create({ to: `+92${phone}`, code });
};

module.exports = { sendOtp, verifyOtp };
