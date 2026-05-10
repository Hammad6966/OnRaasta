const express = require('express');
const Job     = require('../models/Job');
const { verifyToken } = require('../middleware/auth.middleware');

const router = express.Router();

// POST /api/jobs — create job
router.post('/', verifyToken, async (req, res, next) => {
  try {
    const job = await Job.create({ ...req.body, userId: req.user.id });
    return res.status(201).json({ success: true, data: job });
  } catch (err) {
    next(err);
  }
});

// GET /api/jobs — list caller's jobs
router.get('/', verifyToken, async (req, res, next) => {
  try {
    const jobs = await Job.find({ userId: req.user.id }).sort({ createdAt: -1 });
    return res.status(200).json({ success: true, data: jobs });
  } catch (err) {
    next(err);
  }
});

// GET /api/jobs/:id — single job
router.get('/:id', verifyToken, async (req, res, next) => {
  try {
    const job = await Job.findById(req.params.id);
    if (!job) return res.status(404).json({ success: false, message: 'Job not found' });
    return res.status(200).json({ success: true, data: job });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
