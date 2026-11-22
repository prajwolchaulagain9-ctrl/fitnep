import { Router } from "express";

import { AuthenticationError, AuthVerifier } from "./auth";
import { PlatformSessionService, platformSessionHeader } from "./platform_sessions";

export function createSessionRouter(auth: AuthVerifier, sessions: PlatformSessionService): Router {
  const router = Router();
  router.use((request, response, next) => {
    const match = request.header("Authorization")?.trim().match(/^Bearer\s+(\S+)$/i);
    if (!match?.[1]) { next(new AuthenticationError("A Firebase ID token is required.")); return; }
    void auth.verifyIdToken(match[1]).then(actor => {
      response.locals.user = actor;
      next();
    }, next);
  });
  router.use((request, _response, next) => {
    // IDs, roles, permissions and timestamps always come from trusted server state.
    if (Object.keys(request.query).length || (request.body !== undefined &&
      (request.body === null || typeof request.body !== "object" ||
        Array.isArray(request.body) || Object.keys(request.body).length))) {
      next(new AuthenticationError("Session requests must have an empty body and no query parameters.", 403));
      return;
    }
    next();
  });
  router.post("/start", (request, response, next) => {
    void sessions.start(response.locals.user, response.locals.correlationId).then(session => {
      response.json({ data: session });
    }, next);
  });
  router.get("/me", (request, response, next) => {
    void sessions.verify(response.locals.user, request.header(platformSessionHeader)).then(session => {
      response.json({ data: session });
    }, next);
  });
  router.post("/activity", (request, response, next) => {
    void sessions.activity(response.locals.user, request.header(platformSessionHeader)).then(session => {
      response.json({ data: session });
    }, next);
  });
  router.post("/end", (request, response, next) => {
    void sessions.end(response.locals.user, request.header(platformSessionHeader), response.locals.correlationId).then(() => {
      response.status(204).end();
    }, next);
  });
  return router;
}
