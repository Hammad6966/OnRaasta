const express  = require('express');
const Job      = require('../models/Job');
const Mechanic = require('../models/Mechanic');
const { verifyToken } = require('../middleware/auth.middleware');
const { createJob, listJobs, getJob, updateStatus } = require('../controllers/jobs.controller');

const router = express.Router();

// POST /api/jobs — create job (emits job:created via socket)
router.post('/', verifyToken, createJob);

// GET /api/jobs — list caller's jobs
router.get('/', verifyToken, listJobs);

// GET /api/jobs/:id — single job
router.get('/:id', verifyToken, getJob);

// PATCH /api/jobs/:id/status — update job status (emits job:status_changed via socket)
router.patch('/:id/status', verifyToken, updateStatus);

// POST /api/jobs/:id/review — submit rating + review
router.post('/:id/review', verifyToken, async (req, res, next) => {
  try {
    const job = await Job.findOne({ _id: req.params.id, userId: req.user.id });
    if (!job) return res.status(404).json({ success: false, message: 'Job not found' });

    if (job.review && job.review.stars) {
      return res.status(400).json({ success: false, message: 'Already reviewed' });
    }

    const { stars, tags = [], comment = '' } = req.body;
    if (!stars || stars < 1 || stars > 5) {
      return res.status(400).json({ success: false, message: 'Stars must be 1–5' });
    }

    job.review = { stars, tags, comment, createdAt: new Date() };
    await job.save();

    // Recalculate mechanic's average rating
    if (job.mechanicId) {
      const reviews = await Job.find({
        mechanicId: job.mechanicId,
        'review.stars': { $exists: true },
      }).select('review.stars');

      if (reviews.length > 0) {
        const avg =
          reviews.reduce((sum, j) => sum + j.review.stars, 0) / reviews.length;
        await Mechanic.findOneAndUpdate(
          { userId: job.mechanicId },
          { rating: Math.round(avg * 10) / 10 },
        );
      }
    }

    return res.status(200).json({ success: true, message: 'Review submitted' });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
