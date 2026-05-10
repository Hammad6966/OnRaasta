const express = require('express');
const { getNearby } = require('../controllers/mechanics.controller');

const router = express.Router();

// Public — no auth required
router.get('/nearby', getNearby);

module.exports = router;
