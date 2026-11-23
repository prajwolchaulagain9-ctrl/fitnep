const { getAuth } = require('firebase-admin/auth');
const { HttpsError } = require('firebase-functions/v2/https');

const staffRoles = new Set(['admin', 'dietitian', 'staff']);

function normalizedRole(role) {
  return typeof role === 'string' ? role.trim().toLowerCase() : null;
}

function staffSessionMatches(user, session) {
  const claims = user.customClaims;
  return !user.disabled &&
    user.uid === session.uid &&
    normalizedRole(claims?.role) === normalizedRole(session.role) &&
    claims?.staffRoleVersion === session.staffRoleVersion &&
    (claims?.mustChangePassword === true || claims?.must_change_password === true) ===
      (session.mustChangePassword === true || session.must_change_password === true) &&
    user.email === session.email;
}

// Use this at every protected callable entry point. The callable's decoded
// request.auth alone does not reject an ID token issued before a reset.
async function requireValidSession(request, auth = getAuth()) {
  const header = request.rawRequest?.headers?.authorization;
  const bearer = typeof header === 'string' && /^Bearer ([^\s]+)$/i.exec(header);
  if (!request.auth?.uid || !bearer) {
    throw new HttpsError('unauthenticated', 'Sign in to continue.');
  }
  try {
    const token = await auth.verifyIdToken(bearer[1], true);
    if (token.uid !== request.auth.uid) {
      throw new HttpsError('unauthenticated', 'Sign in to continue.');
    }
    if (token.mustChangePassword === true || token.must_change_password === true) {
      throw new HttpsError('failed-precondition', 'Change your temporary password before continuing.');
    }
    if (staffRoles.has(normalizedRole(token.role)) &&
        !staffSessionMatches(await auth.getUser(token.uid), token)) {
      throw new HttpsError('unauthenticated', 'Your staff session changed. Sign in again.');
    }
    return token;
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    if (error.code?.startsWith('auth/') && error.code !== 'auth/internal-error') {
      throw new HttpsError('unauthenticated', 'Your session ended. Sign in again.');
    }
    throw new HttpsError('unavailable', 'Session verification is unavailable. Try again.');
  }
}

module.exports = { requireValidSession, staffSessionMatches };
