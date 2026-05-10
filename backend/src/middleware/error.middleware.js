// eslint-disable-next-line no-unused-vars
const errorHandler = (err, req, res, next) => {
  console.error('[Error]', err.message);

  // Mongoose invalid ObjectId
  if (err.name === 'CastError') {
    return res.status(400).json({ success: false, message: `Invalid value for field: ${err.path}` });
  }

  // Mongoose schema validation failure
  if (err.name === 'ValidationError') {
    const message = Object.values(err.errors).map((e) => e.message).join(', ');
    return res.status(400).json({ success: false, message });
  }

  // MongoDB duplicate key
  if (err.code === 11000) {
    return res.status(409).json({ success: false, message: 'Phone number already registered' });
  }

  return res.status(err.status || 500).json({
    success: false,
    message: err.message || 'Internal server error',
  });
};

module.exports = errorHandler;
