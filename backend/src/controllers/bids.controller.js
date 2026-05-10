const Bid            = require('../models/Bid');
const Job            = require('../models/Job');
const Mechanic       = require('../models/Mechanic');
const { getIo }      = require('../socket/socket');

// ── POST /api/bids — mechanic submits a bid ───────────────────────────────────

const createBid = async (req, res) => {
  try {
    const { jobId, labourCost, partsCost, totalCost, eta } = req.body;

    // Resolve mechanic document from the authenticated user
    const mechanic = await Mechanic.findOne({ userId: req.user.id });
    if (!mechanic) {
      return res.status(404).json({ success: false, message: 'Mechanic profile not found' });
    }

    const bid = new Bid({
      jobId,
      mechanicId: mechanic._id,
      labourCost,
      partsCost:  partsCost || 0,
      totalCost,
      eta,
      status:     'pending',
    });

    await bid.save();

    // Move job into bidding state
    await Job.findByIdAndUpdate(jobId, { status: 'bidding' });

    // Emit bid:new to the job owner's socket room
    try {
      const io = getIo();
      const job = await Job.findById(jobId).populate('userId');
      if (io && job) {
        io.to(`user_${job.userId._id}`).emit('bid:new', {
          bidId:        bid._id,
          jobId:        bid.jobId,
          mechanicId:   mechanic._id,
          mechanicName: req.user.name || 'Mechanic',
          labourCost:   bid.labourCost,
          partsCost:    bid.partsCost,
          totalCost:    bid.totalCost,
          eta:          bid.eta,
          status:       bid.status,
          rating:       mechanic.rating || 0,
          skills:       mechanic.skills || [],
        });
      }
    } catch (e) {
      console.log('Socket emit error:', e.message);
    }

    return res.status(201).json({ success: true, bid });
  } catch (error) {
    return res.status(500).json({ success: false, message: error.message });
  }
};

// ── PATCH /api/bids/:id/accept — user accepts a bid ──────────────────────────

const acceptBid = async (req, res, next) => {
  try {
    const bid = await Bid.findByIdAndUpdate(
      req.params.id,
      { status: 'accepted' },
      { new: true },
    );
    if (!bid) return res.status(404).json({ success: false, message: 'Bid not found' });

    await Job.findByIdAndUpdate(bid.jobId, {
      status:        'accepted',
      mechanicId:    bid.mechanicId,
      acceptedBidId: bid._id,
    });

    return res.status(200).json({ success: true, data: bid });
  } catch (err) {
    next(err);
  }
};

// ── GET /api/bids?jobId= — fetch bids for a job ───────────────────────────────

const getBidsByJob = async (req, res, next) => {
  try {
    const { jobId } = req.query;
    if (!jobId) {
      return res.status(400).json({ success: false, message: 'jobId query param required' });
    }
    const bids = await Bid.find({ jobId }).populate({
      path:     'mechanicId',
      populate: { path: 'userId', select: 'name phone' },
    });
    return res.status(200).json({ success: true, data: bids });
  } catch (err) {
    next(err);
  }
};

module.exports = { createBid, acceptBid, getBidsByJob };
