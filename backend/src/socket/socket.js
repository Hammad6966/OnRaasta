const { Server } = require('socket.io');

// ── Singleton io instance ─────────────────────────────────────────────────────

let _io;

const getIo = () => _io;

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
  _io = new Server(server, {
    cors: { origin: '*' },
  });

  const io = _io;
  io.on('connection', (socket) => {
    console.log(`[Socket] connected: ${socket.id}`);

    // Auto-join user room from auth token
    try {
      const token = socket.handshake.auth?.token;
      if (token) {
        const jwt = require('jsonwebtoken');
        const decoded = jwt.verify(token, process.env.JWT_SECRET);
        const userRoom = `user_${decoded.id}`;
        socket.join(userRoom);
        console.log(`[Socket] Auto-joined room: ${userRoom}`);
        socket.userId = decoded.id;
      }
    } catch (e) {
      console.log('[Socket] Auth error:', e.message);
    }

    // ── Room join (clients request their own room) ─────────────────────────

    socket.on('join_room', ({ room }) => {
      socket.join(room);
      console.log(`[Socket] ${socket.id} joined room: ${room}`);
    });

    // ── Mechanic presence ──────────────────────────────────────────────────

    socket.on('mechanic:go_online', (data) => {
      onlineMechanics.set(socket.id, {
        socketId:  socket.id,
        mechanicId: data.mechanicId,
        lat: data.lat,
        lng: data.lng,
      });
      socket.join(`mechanic_${data.mechanicId}`);
      console.log('[Socket] Mechanic online:', data.mechanicId, 'Total online:', onlineMechanics.size);
    });

    socket.on('mechanic:go_offline', ({ mechanicId }) => {
      onlineMechanics.delete(socket.id);
      console.log(`[Socket] mechanic ${mechanicId} offline`);
    });

    socket.on('mechanic:update_location', ({ lat, lng }) => {
      const entry = onlineMechanics.get(socket.id);
      if (entry) {
        entry.lat = lat;
        entry.lng = lng;
      }
    });

    // ── Job events ─────────────────────────────────────────────────────────

    // Broadcast new job to all online mechanics within 15 km
    socket.on('job:created', (data) => {
      console.log('[Socket] job:created received, online mechanics:', onlineMechanics.size);
      const { lat, lng } = data;
      let count = 0;
      onlineMechanics.forEach((mechanic, socketId) => {
        const distance = haversine(lat, lng, mechanic.lat, mechanic.lng);
        console.log('[Socket] Mechanic distance:', distance, 'km');
        if (distance <= 15) {
          io.to(socketId).emit('job:new_request', data);
          count++;
        }
      });
      console.log('[Socket] Broadcast to', count, 'mechanics');
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
      const entry = onlineMechanics.get(socket.id);
      if (entry) {
        onlineMechanics.delete(socket.id);
        console.log(`[Socket] mechanic ${entry.mechanicId} auto-offlined on disconnect`);
      }
      console.log(`[Socket] disconnected: ${socket.id}`);
    });
  });

  return _io;
};

// ── Server-side broadcast (called from controller after job creation) ─────────

function broadcastJobToMechanics(jobData) {
  console.log('[Socket] Broadcasting job to mechanics. Online count:', onlineMechanics.size);
  const { lat, lng } = jobData;
  let count = 0;
  onlineMechanics.forEach((mechanic, socketId) => {
    const distance = haversine(lat, lng, mechanic.lat, mechanic.lng);
    console.log('[Socket] Mechanic', mechanic.mechanicId, 'distance:', distance.toFixed(2), 'km');
    if (distance <= 15) {
      _io.to(socketId).emit('job:new_request', jobData);
      count++;
    }
  });
  console.log('[Socket] Broadcast to', count, 'mechanics');
}

module.exports = { initSocket, getIo, broadcastJobToMechanics };
