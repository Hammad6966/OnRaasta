require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') });

const mongoose = require('mongoose');
const bcrypt   = require('bcryptjs');
const User     = require('../models/User');

async function seedAdmin() {
  await mongoose.connect(process.env.MONGO_URI);
  console.log('Connected to MongoDB');

  const phone = '3000000000';
  const email = 'admin@onraasta.com';

  const existing = await User.findOne({ $or: [{ phone }, { email }] });
  if (existing) {
    console.log('Admin user already exists:', existing.email || existing.phone);
    await mongoose.disconnect();
    return;
  }

  const passwordHash = await bcrypt.hash('admin123', 12);

  await User.create({
    name:         'Admin',
    phone,
    email,
    passwordHash,
    role:        'admin',
    isVerified:  true,
  });

  console.log('Admin created successfully');
  console.log('  Email:    admin@onraasta.com');
  console.log('  Password: admin123');

  await mongoose.disconnect();
}

seedAdmin().catch((err) => {
  console.error('Seed failed:', err);
  process.exit(1);
});
