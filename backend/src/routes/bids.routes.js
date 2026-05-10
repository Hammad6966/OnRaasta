const express = require('express');
const Bid     = require('../models/Bid');
const Job     = require('../models/Job');
const { verifyToken } = require('../middleware/auth.middleware');

const router = express.Router();

// POST /api/bids — mechanic submits a bid
router.post('/', verifyToken, async (req, res, next) => {
  try {
    const bid = await Bid.create(req.body);
    return res.status(201).json({ success: true, data: bid });
  } catch (err) {
    next(err);
  }
});

// PATCH /api/bids/:id/accept — user accepts a bid
router.patch('/:id/accept', verifyToken, async (req, res, next) => {
  try {
    const bid = await Bid.findByIdAndUpdate(
      req.params.id,
      { status: 'accepted' },
      { new: true },
    );
    if (!bid) return res.status(404).json({ success: false, message: 'Bid not found' });

    // Reflect on the job
    await Job.findByIdAndUpdate(bid.jobId, {
      status:        'accepted',
      mechanicId:    bid.mechanicId,
      acceptedBidId: bid._id,
    });

    return res.status(200).json({ success: true, data: bid });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
