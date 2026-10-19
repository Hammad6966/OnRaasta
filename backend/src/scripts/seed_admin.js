// Explicit operator-only provisioning; no public route creates administrators.
require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') });
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
const User = require('../models/User');
async function seedAdmin() {
  const { ADMIN_EMAIL: email, ADMIN_PHONE: phone, ADMIN_PASSWORD: password } = process.env;
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
      !/^\d{10}$/.test(phone || '') || typeof password !== 'string' || password.length < 12 || password.length > 128) {
    throw new Error('Invalid provisioning configuration');
  }
  await mongoose.connect(process.env.MONGO_URI);
  try {
    const normalizedEmail = email.toLowerCase().trim();
    if (await User.exists({ $or: [{ phone }, { email: normalizedEmail }] })) throw new Error('Account already exists');
    await User.create({ name: process.env.ADMIN_NAME || 'Admin', phone, email: normalizedEmail,
      passwordHash: await bcrypt.hash(password, 12), role: 'admin', isVerified: true, isActive: true });
    console.log('Administrator provisioned');
  } finally { await mongoose.disconnect(); }
}
seedAdmin().catch(() => { console.error('Administrator provisioning failed; check configuration and existing account'); process.exitCode = 1; });
