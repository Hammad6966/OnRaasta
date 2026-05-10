const Mechanic = require('../models/Mechanic');

// ── Haversine distance (km) ───────────────────────────────────────────────────

const haversine = (lat1, lng1, lat2, lng2) => {
  const R    = 6371;
  const dLat = (lat2 - lat1) * (Math.PI / 180);
  const dLng = (lng2 - lng1) * (Math.PI / 180);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * (Math.PI / 180)) *
    Math.cos(lat2 * (Math.PI / 180)) *
    Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
};

// ── Controllers ───────────────────────────────────────────────────────────────

/**
 * GET /api/mechanics/nearby?lat=&lng=
 * Returns approved, online mechanics within 15 km, sorted by distance.
 */
const getNearby = async (req, res, next) => {
  try {
    const { lat, lng } = req.query;
    if (!lat || !lng) {
      return res.status(400).json({ success: false, message: 'lat and lng query params are required' });
    }

    const userLat = parseFloat(lat);
    const userLng = parseFloat(lng);

    const mechanics = await Mechanic.find({ isApproved: true, isOnline: true })
      .populate('userId', 'name phone');

    const nearby = mechanics
      .map((m) => ({ ...m.toObject(), distance: haversine(userLat, userLng, m.lat, m.lng) }))
      .filter((m) => m.distance <= 15)
      .sort((a, b) => a.distance - b.distance);

    return res.status(200).json({ success: true, data: nearby });
  } catch (err) {
    next(err);
  }
};

module.exports = { getNearby };
