const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const { apiLimiter } = require('./middleware/rate-limit.middleware');
const app = express();
const mongoose = require('mongoose');
// Liveness is deliberately independent of MongoDB; readiness is not.
app.get('/health', (req, res) => res.json({ status: 'ok' }));
app.get('/ready', async (req, res) => {
  if (process.env.INFRA_READ_ONLY === 'true' || mongoose.connection.readyState !== 1) return res.status(503).json({ status: 'not_ready' });
  try {
    await mongoose.connection.db.command({ ping: 1 }, { timeoutMS: 2000 });
    res.json({ status: 'ready' });
  } catch { res.status(503).json({ status: 'not_ready' }); }
});
app.use(cors({ origin: require('./utils/cors-origins')() }));
app.use(helmet());
if (process.env.NODE_ENV !== 'test') app.use(morgan('dev'));
app.use('/api', apiLimiter);
app.use('/api', (req, res, next) => {
  if (process.env.INFRA_READ_ONLY === 'true' && !['GET', 'HEAD', 'OPTIONS'].includes(req.method)) {
    return res.status(503).json({ success: false, message: 'Read-only infrastructure verification mode' });
  }
  next();
});
app.use(express.json({ limit: '10mb' }));
app.use('/api/auth', require('./routes/auth.routes'));
app.use('/api/users', require('./routes/users.routes'));
app.use('/api/mechanics', require('./routes/mechanics.routes'));
app.use('/api/jobs', require('./routes/jobs.routes'));
app.use('/api/bids', require('./routes/bids.routes'));
app.use('/api/admin', require('./routes/admin.routes'));
app.use(require('./middleware/error.middleware'));
module.exports = app;
