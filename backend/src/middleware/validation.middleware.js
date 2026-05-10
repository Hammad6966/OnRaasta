const { validationResult } = require('express-validator');

/**
 * Reads express-validator results and short-circuits with 400 on failure.
 * Place after body() validator chains in route definitions.
 */
const validateRequest = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ success: false, errors: errors.array() });
  }
  next();
};

module.exports = { validateRequest };
