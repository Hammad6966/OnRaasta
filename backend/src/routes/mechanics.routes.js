const express = require('express');
const { getNearby, getProfile, getOpenRequests, updateProfile } = require('../controllers/mechanics.controller');
const { verifyToken, verifyRole } = require('../middleware/auth.middleware');
const v = require('../middleware/request-validation');

const router = express.Router();

// Validated public discovery; only safe live-presence fields are returned.
// Public — no auth required
router.get('/nearby', v.nearby, getNearby);

// Protected
router.get('/history', verifyToken, verifyRole('mechanic'), require('../services/history.service').list);
router.get('/earnings', verifyToken, verifyRole('mechanic'), require('../services/history.service').earnings);
router.get('/requests', verifyToken, verifyRole('mechanic'), getOpenRequests);
router.get('/profile', verifyToken, verifyRole('mechanic'), getProfile);
router.patch('/profile', verifyToken, verifyRole('mechanic'), v.mechanicProfile, updateProfile);

router.get('/:mechanicId/reviews', verifyToken, v.mechanicId, require('../services/review.service').list);

module.exports = router;
