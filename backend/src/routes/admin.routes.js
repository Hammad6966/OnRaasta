const express    = require('express');
const bcrypt     = require('bcryptjs');
const jwt        = require('jsonwebtoken');
const mongoose   = require('mongoose');

const User     = require('../models/User');
const Mechanic = require('../models/Mechanic');
const Job      = require('../models/Job');
const { verifyToken, verifyRole } = require('../middleware/auth.middleware');

const router = express.Router();

// ── Auth guard shorthand ──────────────────────────────────────────────────────
const adminOnly = [verifyToken, verifyRole('admin')];

// ── POST /api/admin/login ─────────────────────────────────────────────────────
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ success: false, message: 'Email and password required' });
    }

    const user = await User.findOne({ email: email.toLowerCase().trim(), role: 'admin' });
    if (!user) {
      return res.status(401).json({ success: false, message: 'Invalid credentials' });
    }

    const match = await bcrypt.compare(password, user.passwordHash);
    if (!match) {
      return res.status(401).json({ success: false, message: 'Invalid credentials' });
    }

    const token = jwt.sign(
      { id: user._id, role: user.role, name: user.name },
      process.env.JWT_SECRET,
      { expiresIn: '8h' },
    );

    res.json({ success: true, token, name: user.name });
  } catch (err) {
    console.error('[admin/login]', err);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// ── GET /api/admin/stats ─────────────────────────────────────── (public) ─────
router.get('/stats', async (req, res) => {
  try {
    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);

    const [
      totalUsers,
      totalMechanics,
      activeJobs,
      pendingVerifications,
      revenueAgg,
      newUsersToday,
    ] = await Promise.all([
      User.countDocuments({ role: 'user' }),
      Mechanic.countDocuments(),
      Job.countDocuments({ status: { $in: ['accepted', 'en_route', 'in_progress'] } }),
      Mechanic.countDocuments({ 'documents.status': 'pending' }),
      Job.aggregate([
        { $match: { status: 'completed', finalCost: { $exists: true, $ne: null } } },
        { $group: { _id: null, total: { $sum: '$finalCost' } } },
      ]),
      User.countDocuments({ role: 'user', createdAt: { $gte: todayStart } }),
    ]);

    const totalRevenue = revenueAgg[0]?.total ?? 0;

    res.json({
      success: true,
      data: {
        totalUsers,
        totalMechanics,
        activeJobs,
        pendingVerifications,
        totalRevenue,
        newUsersToday,
      },
    });
  } catch (err) {
    console.error('[admin/stats]', err);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// ── GET /api/admin/jobs-chart ─────────────────────────────────────────────────
router.get('/jobs-chart', async (req, res) => {
  try {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    // Last 7 days from yesterday to today
    const results = [];
    for (let i = 6; i >= 0; i--) {
      const start = new Date();
      start.setDate(start.getDate() - i);
      start.setHours(0, 0, 0, 0);
      const end = new Date(start);
      end.setHours(23, 59, 59, 999);

      const count = await Job.countDocuments({ createdAt: { $gte: start, $lte: end } });
      results.push({ day: days[start.getDay()], jobs: count });
    }

    res.json({ success: true, data: results });
  } catch (err) {
    console.error('[admin/jobs-chart]', err);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// ── GET /api/admin/faults-chart ───────────────────────────────────────────────
router.get('/faults-chart', async (req, res) => {
  try {
    const agg = await Job.aggregate([
      { $match: { 'aiDiagnosis.fault_class': { $exists: true, $ne: null } } },
      { $group: { _id: '$aiDiagnosis.fault_class', value: { $sum: 1 } } },
      { $sort: { value: -1 } },
      { $limit: 6 },
    ]);

    const data = agg.map((d) => ({
      name: d._id.replace(/_/g, ' '),
      value: d.value,
    }));

    res.json({ success: true, data });
  } catch (err) {
    console.error('[admin/faults-chart]', err);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// ── GET /api/admin/recent-jobs ────────────────────────────────────────────────
router.get('/recent-jobs', async (req, res) => {
  try {
    const jobs = await Job.find()
      .sort({ createdAt: -1 })
      .limit(10)
      .populate('userId', 'name phone')
      .populate({
        path: 'mechanicId',
        populate: { path: 'userId', select: 'name' },
      })
      .lean();

    const data = jobs.map((j) => ({
      jobId:    j._id.toString().slice(-6).toUpperCase(),
      _id:      j._id,
      user:     j.userId?.name ?? 'Unknown',
      status:   j.status,
      fault:    j.aiDiagnosis?.fault_class?.replace(/_/g, ' ') ?? '—',
      amount:   j.finalCost ?? null,
      createdAt: j.createdAt,
    }));

    res.json({ success: true, data });
  } catch (err) {
    console.error('[admin/recent-jobs]', err);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// ── GET /api/admin/users ──────────────────────────────────────────────────────
router.get('/users', ...adminOnly, async (req, res) => {
  try {
    const users = await User.find({ role: { $ne: 'admin' } })
      .sort({ createdAt: -1 })
      .limit(50)
      .lean();

    res.json({ success: true, data: users });
  } catch (err) {
    console.error('[admin/users]', err);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// ── GET /api/admin/verification ───────────────────────────────────────────────
router.get('/verification', ...adminOnly, async (req, res) => {
  try {
    const mechanics = await Mechanic.find({ 'documents.status': 'pending' })
      .populate('userId', 'name phone')
      .sort({ createdAt: -1 })
      .lean();

    res.json({ success: true, data: mechanics });
  } catch (err) {
    console.error('[admin/verification]', err);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// ── PATCH /api/admin/verification/:mechanicId ─────────────────────────────────
router.patch('/verification/:mechanicId', ...adminOnly, async (req, res) => {
  try {
    const { status, rejectionReason } = req.body; // 'verified' | 'rejected'
    const mechanic = await Mechanic.findByIdAndUpdate(
      req.params.mechanicId,
      {
        'documents.status': status,
        ...(rejectionReason && { 'documents.rejectionReason': rejectionReason }),
        ...(status === 'verified' && { isApproved: true }),
      },
      { new: true },
    );

    if (!mechanic) return res.status(404).json({ success: false, message: 'Mechanic not found' });

    res.json({ success: true, data: mechanic });
  } catch (err) {
    console.error('[admin/verification patch]', err);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

module.exports = router;
