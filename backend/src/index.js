require('dotenv').config();
const http = require('http');
const mongoose = require('mongoose');
const app = require('./app');
const Bid = require('./models/Bid');
const { initSocket } = require('./socket/socket');
const server = http.createServer(app);
const readOnly = process.env.INFRA_READ_ONLY === 'true';
async function connectWithRetry(attempt = 1) {
  try {
    const uri = process.env.MONGODB_URI || process.env.MONGO_URI;
    if (process.env.MONGODB_URI && process.env.MONGO_URI && process.env.MONGODB_URI !== process.env.MONGO_URI) throw new Error('Conflicting MongoDB configuration');
    await mongoose.connect(uri, { autoIndex: !readOnly, autoCreate: !readOnly });
    // Never silently drop indexes or repair existing records during startup.
    if (!readOnly) {
      await Bid.createIndexes();
      // Additive initialization: audit writes must not create a collection in a transaction.
      const AdminLog = require('./models/AdminLog');
      await AdminLog.createCollection();
      await AdminLog.createIndexes();
      const DocumentReview = require('./models/DocumentReview');
      await DocumentReview.createCollection();
      await DocumentReview.createIndexes();
      // Socket startup includes expired-location cleanup writes. Never run it
      // against the application database during read-only infrastructure probes.
      initSocket(server);
    }
    const port = process.env.PORT || 5000;
    server.listen(port, process.env.HOST || '0.0.0.0', () => console.log(`OnRaasta backend running on port ${port}${readOnly ? ' (read-only verification)' : ''}`));
  } catch {
    if (attempt < 5) setTimeout(() => connectWithRetry(attempt + 1), 5000);
    else { console.error('Database connection or required index setup failed'); process.exit(1); }
  }
}
connectWithRetry();
