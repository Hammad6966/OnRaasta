const Job = require('../models/Job');
const { broadcastJobToMechanics, getIo } = require('../socket/socket');

// POST /api/jobs
const createJob = async (req, res, next) => {
  try {
    const job = await Job.create({ ...req.body, userId: req.user.id });

    // Broadcast to nearby online mechanics via socket
    try {
      broadcastJobToMechanics({
        jobId:       job._id.toString(),
        description: job.description,
        location:    job.location,
        aiDiagnosis: job.aiDiagnosis,
        userId:      job.userId.toString(),
        lat:         job.location.lat,
        lng:         job.location.lng,
      });
    } catch (e) {
      console.log('Broadcast error:', e.message);
    }

    return res.status(201).json({ success: true, data: job });
  } catch (err) {
    next(err);
  }
};

// GET /api/jobs
const listJobs = async (req, res, next) => {
  try {
    const jobs = await Job.find({ userId: req.user.id }).sort({ createdAt: -1 });
    return res.status(200).json({ success: true, data: jobs });
  } catch (err) {
    next(err);
  }
};

// GET /api/jobs/:id
const getJob = async (req, res, next) => {
  try {
    const job = await Job.findById(req.params.id);
    if (!job) return res.status(404).json({ success: false, message: 'Job not found' });
    return res.status(200).json({ success: true, data: job });
  } catch (err) {
    next(err);
  }
};

// PATCH /api/jobs/:id/status
const updateStatus = async (req, res, next) => {
  try {
    const job = await Job.findById(req.params.id);
    if (!job) return res.status(404).json({ success: false, message: 'Job not found' });

    job.status = req.body.status;
    await job.save();

    try {
      const io = getIo();
      const payload = { jobId: job._id.toString(), status: job.status };
      io.to(`job_${job._id}`).emit('job:status_changed', payload);
      io.to(`user_${job.userId}`).emit('job:status_changed', payload);
      console.log('[Socket] job:status_changed emitted to job and user rooms:', job.status);
    } catch (e) {
      console.log('Socket emit error:', e.message);
    }

    return res.status(200).json({ success: true, job });
  } catch (err) {
    next(err);
  }
};

module.exports = { createJob, listJobs, getJob, updateStatus };
