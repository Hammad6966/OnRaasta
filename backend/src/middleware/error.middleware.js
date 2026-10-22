module.exports = (err, req, res, next) => {
  if (res.headersSent) return next(err);
  if (err.name === 'MulterError') return res.status(err.code === 'LIMIT_FILE_SIZE' ? 413 : 400).json({ success: false, message: err.code === 'LIMIT_FILE_SIZE' ? 'File exceeds the 8 MB limit' : 'Upload one file using the file field' });
  if (['JsonWebTokenError', 'TokenExpiredError', 'NotBeforeError'].includes(err.name)) {
    return res.status(401).json({ success: false, message: 'Invalid or expired token' });
  }
  if (['CastError', 'ValidationError'].includes(err.name) || err.type === 'entity.parse.failed') {
    return res.status(400).json({ success: false, message: 'Invalid request' });
  }
  if (err.code === 11000) return res.status(409).json({ success: false, message: 'Conflicting or duplicate record' });
  if (err.code === 20 || err.codeName === 'IllegalOperation') {
    return res.status(503).json({ success: false, message: 'Transactional database unavailable' });
  }
  const status = [400, 401, 403, 404, 409, 413, 429, 503].includes(err.status) ? err.status : 500;
  res.status(status).json({ success: false, message: status === 500 ? 'Internal server error' : err.message, ...(['ACCESS_TOKEN_EXPIRED', 'ACCOUNT_UNAVAILABLE'].includes(err.publicCode) ? { code: err.publicCode } : {}) });
};
