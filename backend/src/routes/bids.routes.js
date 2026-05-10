const express = require('express');
const { verifyToken } = require('../middleware/auth.middleware');
const { createBid, acceptBid, getBidsByJob } = require('../controllers/bids.controller');

const router = express.Router();

router.post('/',             verifyToken, createBid);
router.patch('/:id/accept',  verifyToken, acceptBid);
router.get('/',              verifyToken, getBidsByJob);

module.exports = router;
