const { getAuth } = require('firebase-admin/auth');
const { HttpsError } = require('firebase-functions/v2/https');

// Use this at every protected callable entry point. The callable's decoded
// request.auth alone does not reject an ID token issued before a reset.
async function requireValidSession(request, auth = getAuth()) {
  const header = request.rawRequest?.headers?.authorization;
  const bearer = typeof header === 'string' && /^Bearer ([^\s]+)$/i.exec(header);
  if (!request.auth?.uid || !bearer) {
    throw new HttpsError('unauthenticated', 'Sign in to continue.');
  }
  let token;
  try {
    token = await auth.verifyIdToken(bearer[1], true);
  } catch (error) {
    if (error.code?.startsWith('auth/') && error.code !== 'auth/internal-error') {
      throw new HttpsError('unauthenticated', 'Your session ended. Sign in again.');
    }
    throw new HttpsError('unavailable', 'Session verification is unavailable. Try again.');
  }
  if (token.uid !== request.auth.uid) {
    throw new HttpsError('unauthenticated', 'Sign in to continue.');
  }
  return token;
}

module.exports = { requireValidSession };
