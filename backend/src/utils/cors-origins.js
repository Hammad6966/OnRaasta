// Explicit operator origins win. Only local development gains the loopback alias;
// production retains its previous localhost-only fallback, never a wildcard.
module.exports = () => process.env.CORS_ORIGINS
  ? process.env.CORS_ORIGINS.split(',').map(s => s.trim()).filter(Boolean)
  : process.env.NODE_ENV === 'production'
    ? ['http://localhost:3000']
    : ['http://localhost:3000', 'http://127.0.0.1:3000'];
