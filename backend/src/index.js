require('dotenv').config();

const express  = require('express');
const http     = require('http');
const mongoose = require('mongoose');
const cors     = require('cors');
const helmet   = require('helmet');
const morgan   = require('morgan');

const authRoutes      = require('./routes/auth.routes');
const usersRoutes     = require('./routes/users.routes');
const mechanicsRoutes = require('./routes/mechanics.routes');
const jobsRoutes      = require('./routes/jobs.routes');
const bidsRoutes      = require('./routes/bids.routes');
const { initSocket }  = require('./socket/socket');
const errorHandler    = require('./middleware/error.middleware');

// ── Express app ───────────────────────────────────────────────────────────────

const app    = express();
const server = http.createServer(app);

app.use(cors());
app.use(helmet());
app.use(morgan('dev'));
app.use(express.json({ limit: '10mb' }));

// ── Routes ────────────────────────────────────────────────────────────────────

app.use('/api/auth',      authRoutes);
app.use('/api/users',     usersRoutes);
app.use('/api/mechanics', mechanicsRoutes);
app.use('/api/jobs',      jobsRoutes);
app.use('/api/bids',      bidsRoutes);

// ── Global error handler (must be last) ──────────────────────────────────────

app.use(errorHandler);

// ── Socket.IO ─────────────────────────────────────────────────────────────────

initSocket(server);

// ── MongoDB with retry ────────────────────────────────────────────────────────

mongoose.connection.once('open', async () => {
  try {
    await mongoose.connection.collection('users').dropIndex('email_1');
    console.log('Dropped email index');
  } catch (e) {
    // index may not exist — safe to ignore
  }
});

const connectWithRetry = async (attempt = 1) => {
  try {
    await mongoose.connect(process.env.MONGO_URI);
    console.log('MongoDB connected');
  } catch (err) {
    if (attempt < 5) {
      console.warn(`MongoDB connection attempt ${attempt} failed — retrying in 5 s…`);
      setTimeout(() => connectWithRetry(attempt + 1), 5000);
    } else {
      console.error('MongoDB connection failed after 5 attempts:', err.message);
      process.exit(1);
    }
  }
};

connectWithRetry();

// ── Listen ────────────────────────────────────────────────────────────────────

const PORT = process.env.PORT || 5000;
server.listen(PORT, () => {
  console.log(`OnRaasta backend running on port ${PORT}`);
});
