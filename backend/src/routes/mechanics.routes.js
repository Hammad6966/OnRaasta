const express = require('express');
const { getNearby, getProfile } = require('../controllers/mechanics.controller');
const { verifyToken } = require('../middleware/auth.middleware');

const router = express.Router();

// Public — no auth required
router.get('/nearby', getNearby);

// Protected
router.get('/profile', verifyToken, getProfile);

module.exports = router;
