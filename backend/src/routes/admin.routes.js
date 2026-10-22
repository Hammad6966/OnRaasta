const express    = require('express');
const bcrypt     = require('bcryptjs');
const { signAccessToken } = require('../services/access.service');
const v = require('../middleware/request-validation');
const { authLimiter } = require('../middleware/rate-limit.middleware');

const User     = require('../models/User');
const Mechanic = require('../models/Mechanic');
const Job      = require('../models/Job');
const { verifyToken, verifyRole } = require('../middleware/auth.middleware');

const router = express.Router();

// ── Auth guard shorthand ──────────────────────────────────────────────────────
const adminOnly = [verifyToken, verifyRole('admin')];

// ── POST /api/admin/login ─────────────────────────────────────────────────────
router.post('/login', authLimiter, v.adminLogin, async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ success: false, message: 'Email and password required' });
    }

    const user = await User.findOne({ email: email.toLowerCase().trim(), role: 'admin' });
    if (!user) {
      return res.status(401).json({ success: false, message: 'Invalid credentials' });
    }

    if (!user.isActive || !user.isVerified) {
      return res.status(403).json({ success: false, message: 'Account is inactive or unverified' });
    }
    if (user.lockoutUntil && user.lockoutUntil > Date.now()) {
      return res.status(429).json({ success: false, message: 'Account temporarily locked' });
    }
    const match = await bcrypt.compare(password, user.passwordHash);
    if (!match) {
      user.failedLoginAttempts += 1;
      if (user.failedLoginAttempts >= 5) user.lockoutUntil = new Date(Date.now() + 30 * 60 * 1000);
      await user.save();
      return res.status(401).json({ success: false, message: 'Invalid credentials' });
    }

    user.failedLoginAttempts = 0;
    user.lockoutUntil = undefined;
    await user.save();
    const token = signAccessToken(user);

    res.json({ success: true, token, name: user.name });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// ── GET /api/admin/stats ─────────────────────────────────────── (admin only) ─────
router.use(...adminOnly);
const documents = require('../services/documents.service');
router.get('/verification/:mechanicId/documents', v.mechanicId, documents.get);
router.post('/verification/:mechanicId/documents/review', v.mechanicId, documents.review);
router.get('/documents/:id', v.id, require('../services/media.service').privateFile);

router.get('/stats', async (req, res) => {
  try {
    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);

    const [
      totalUsers,
      totalMechanics,
      activeJobs,
      bookedTotals,
      newUsersToday,
      statusCounts,
    ] = await Promise.all([
      User.countDocuments({ role: 'user' }),
      require('../services/admin.service').applicationCounts(),
      Job.countDocuments({ status: { $in: ['accepted', 'en_route', 'arrived', 'in_progress'] } }),
      require('../services/history.service').summary({}),
      User.countDocuments({ role: 'user', createdAt: { $gte: todayStart } }),
      Promise.all(v.states.map(status => Job.countDocuments({ status }))),
    ]);

    // Legacy numeric display adapter; exact accounting remains integer paisa.
    const totalRevenue = Number(bookedTotals.grossMinor) / 100;

    res.json({
      success: true,
      data: {
        totalUsers,
        totalMechanics: totalMechanics.eligibleApproved,
        mechanicApplications: totalMechanics,
        approvedMechanics: totalMechanics.eligibleApproved,
        activeJobs,
        pendingVerifications: totalMechanics.pending,
        totalRevenue,
        revenueBasis: 'booked_not_paid',
        bookedTotals,
        bookedCommissionMinor: bookedTotals.commissionMinor,
        newUsersToday,
        jobsByStatus: Object.fromEntries(v.states.map((status, i) => [status, statusCounts[i]])),
      },
    });
  } catch (err) {
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
      amount:   require('../services/accounting.service').accounted(j) ? j.accounting.totalMinor / 100 : null,
      createdAt: j.createdAt,
    }));

    res.json({ success: true, data });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

const management = require('../services/admin.service');
router.get('/users', management.listUsers);
router.get('/users/:id', v.id, management.detail);
router.patch('/users/:id/status', v.id, management.accountStatus);
router.get('/verification', management.applications);
// Existing path now decides account approval, never document verification.
router.patch('/verification/:mechanicId', v.mechanicId, management.decide);
router.get('/audit-logs', management.logs);
module.exports = router;
