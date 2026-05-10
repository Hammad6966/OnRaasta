const { Server } = require('socket.io');

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

// ── In-memory mechanic presence store ────────────────────────────────────────
// mechanicId (string) → { socketId, mechanicId, lat, lng }

const onlineMechanics = new Map();

// ── Init ──────────────────────────────────────────────────────────────────────

const initSocket = (server) => {
  const io = new Server(server, {
    cors: { origin: '*' },
  });

  io.on('connection', (socket) => {
    console.log(`[Socket] connected: ${socket.id}`);

    // ── Mechanic presence ──────────────────────────────────────────────────

    socket.on('mechanic:go_online', ({ mechanicId, lat, lng }) => {
      onlineMechanics.set(String(mechanicId), { socketId: socket.id, mechanicId, lat, lng });
      socket.join(`mechanic_${mechanicId}`);
      console.log(`[Socket] mechanic ${mechanicId} online`);
    });

    socket.on('mechanic:go_offline', ({ mechanicId }) => {
      onlineMechanics.delete(String(mechanicId));
      console.log(`[Socket] mechanic ${mechanicId} offline`);
    });

    socket.on('mechanic:update_location', ({ mechanicId, lat, lng }) => {
      const entry = onlineMechanics.get(String(mechanicId));
      if (entry) {
        entry.lat = lat;
        entry.lng = lng;
        // socketId unchanged — no need to re-set
      }
    });

    // ── Job events ─────────────────────────────────────────────────────────

    // Broadcast new job to all online mechanics within 15 km
    socket.on('job:created', ({ jobId, lat, lng, userId }) => {
      onlineMechanics.forEach((mechanic) => {
        const dist = haversine(lat, lng, mechanic.lat, mechanic.lng);
        if (dist <= 15) {
          io.to(mechanic.socketId).emit('job:new_request', {
            jobId,
            lat,
            lng,
            userId,
            distance: parseFloat(dist.toFixed(2)),
          });
        }
      });
    });

    socket.on('job:status_changed', ({ jobId, status }) => {
      io.to(`job_${jobId}`).emit('job:status_changed', { jobId, status });
    });

    // ── Bid events ─────────────────────────────────────────────────────────

    // Notify user that a new bid arrived
    socket.on('bid:new', ({ userId, bidData }) => {
      io.to(`user_${userId}`).emit('bid:new', bidData);
    });

    // Join both parties to the job room once a bid is accepted
    socket.on('bid:accepted', ({ jobId, userSocketId, mechanicSocketId }) => {
      const room = `job_${jobId}`;
      socket.join(room);
      io.sockets.sockets.get(userSocketId)?.join(room);
      io.sockets.sockets.get(mechanicSocketId)?.join(room);
      io.to(room).emit('bid:accepted', { jobId });
    });

    // ── SOS ────────────────────────────────────────────────────────────────

    socket.on('sos:triggered', (data) => {
      io.of('/admin').emit('sos:triggered', data);
    });

    // ── Disconnect cleanup ─────────────────────────────────────────────────

    socket.on('disconnect', () => {
      onlineMechanics.forEach((mechanic, mechanicId) => {
        if (mechanic.socketId === socket.id) {
          onlineMechanics.delete(mechanicId);
          console.log(`[Socket] mechanic ${mechanicId} auto-offlined on disconnect`);
        }
      });
      console.log(`[Socket] disconnected: ${socket.id}`);
    });
  });

  return io;
};

module.exports = { initSocket };
