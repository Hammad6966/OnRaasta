const Job = require('../models/Job');
const Vehicle = require('../models/Vehicle');
const { broadcastJobToMechanics, publishJobStatus } = require('../socket/socket');
const { canViewJob, sameId } = require('../services/access.service');
const fail = require('../utils/http-error');
const { withJobLock } = require('../services/job-tracking.service');
const { transitionJob } = require('../services/job-lifecycle.service');

const createJob = async (req, res, next) => {
  try {
    if (req.user.role !== 'user') throw fail(403, 'Driver access required');
    const { description, location, aiDiagnosis, photos, vehicleId } = req.body;
    const create = async (session) => {
      if (vehicleId) {
      const vehicle = await Vehicle.findById(vehicleId).session(session);
      if (!vehicle) throw fail(404, 'Vehicle not found');
      if (!sameId(vehicle.userId, req.user.id)) throw fail(403, 'Vehicle does not belong to driver');
      }
      const data = { userId: req.user.id, description: description.trim(), location, aiDiagnosis, photos, vehicleId };
      return session ? (await Job.create([data], { session }))[0] : Job.create(data);
    };
    const job = vehicleId ? await require('./users.controller').withVehicles(req.user.id, create) : await create();
    // Persist first; an unavailable socket must not turn a saved request into an HTTP failure.
    try {
      await broadcastJobToMechanics({ jobId: String(job._id), description: job.description,
        location: job.location, aiDiagnosis: job.aiDiagnosis, userId: String(job.userId),
        lat: job.location.lat, lng: job.location.lng });
    } catch { /* HTTP persistence remains authoritative. */ }
    res.status(201).json({ success: true, data: job });
  } catch (err) { next(err); }
};
const listJobs = require('../services/history.service').list;
const getJob = async (req, res, next) => {
  try {
    const job = await Job.findById(req.params.id);
    if (!job) throw fail(404, 'Job not found');
    if (!await canViewJob(req.user, job)) throw fail(403, 'Job access forbidden');
    res.json({ success: true, data: job });
  } catch (err) { next(err); }
};
const updateStatus = async (req, res, next) => {
  try {
    const job = await withJobLock(req.params.id, async () => {
      const saved = await transitionJob(req.user, req.params.id, req.body);
      try { await publishJobStatus(saved); } catch { /* HTTP recovery. */ }
      return saved;
    });
    // Notifications are post-commit hints. HTTP still reports a persisted success
    // if the realtime transport fails; assignment reads recover missed events.
    res.json({ success: true, job });
  } catch (err) { next(err); }
};
module.exports = { createJob, listJobs, getJob, updateStatus };
