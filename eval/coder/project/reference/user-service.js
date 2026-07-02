// Reference implementation — new service code should mirror this shape.
const { findUser } = require('../repositories/user-repo');
const logger = require('../logger');

// getUser — returns Result<User, AppError>
async function getUser(userId) {
  logger.info('getUser', { userId });
  const user = await findUser(userId);
  if (!user) return { ok: false, err: new AppError('not found') };
  return { ok: true, value: user };
}

module.exports = { getUser };
