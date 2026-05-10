const express = require('express');
const User    = require('../models/User');
const { verifyToken } = require('../middleware/auth.middleware');

const router = express.Router();

// GET /api/users/profile
router.get('/profile', verifyToken, async (req, res, next) => {
  try {
    const user = await User.findById(req.user.id).select('-passwordHash');
    if (!user) return res.status(404).json({ success: false, message: 'User not found' });
    return res.status(200).json({ success: true, data: user });
  } catch (err) {
    next(err);
  }
});

// PATCH /api/users/profile
router.patch('/profile', verifyToken, async (req, res, next) => {
  try {
    const { name, email, emergencyContacts } = req.body;
    const user = await User.findByIdAndUpdate(
      req.user.id,
      { ...(name && { name }), ...(email && { email }), ...(emergencyContacts && { emergencyContacts }) },
      { new: true, runValidators: true },
    ).select('-passwordHash');
    if (!user) return res.status(404).json({ success: false, message: 'User not found' });
    return res.status(200).json({ success: true, data: user });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
