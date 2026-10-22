const express  = require('express');
const { verifyToken, verifyRole } = require('../middleware/auth.middleware');
const { createJob, listJobs, getJob, updateStatus } = require('../controllers/jobs.controller');
const { getAssignment, listAssignments, opportunity } = require('../services/assignment.service');

const v = require('../middleware/request-validation');
const router = express.Router();

// POST /api/jobs — create job (emits job:created via socket)
router.post('/', verifyToken, verifyRole('user'), v.job, createJob);

// GET /api/jobs — list caller's jobs
router.get('/', verifyToken, verifyRole('user'), listJobs);

router.get('/assignments', verifyToken, verifyRole('user', 'mechanic'), listAssignments);
router.get('/:id/recommendations', verifyToken, verifyRole('user'), v.id, require('../services/recommendation.service').recommend);
router.get('/:id/assignment', verifyToken, v.id, getAssignment);
router.get('/:id/messages', verifyToken, verifyRole('user', 'mechanic'), v.id, require('../services/chat.service').list);
router.post('/:id/messages', verifyToken, verifyRole('user', 'mechanic'), v.id, require('../services/chat.service').send);
router.get('/:id/location', verifyToken, v.id, require('../services/job-tracking.service').latest);
router.get('/:id/opportunity', verifyToken, verifyRole('mechanic'), v.id, opportunity);

// GET /api/jobs/:id — single job
router.get('/:id', verifyToken, v.id, getJob);

// PATCH /api/jobs/:id/status — update job status (emits job:status_changed via socket)
router.patch('/:id/status', verifyToken, v.id, v.status, updateStatus);

// POST /api/jobs/:id/review — submit rating + review
router.post('/:id/review', verifyToken, verifyRole('user'), v.id, v.review, require('../services/review.service').submit);

module.exports = router;
