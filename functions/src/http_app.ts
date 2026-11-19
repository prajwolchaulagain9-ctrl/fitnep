import express, {
  NextFunction,
  Request,
  Response,
  RequestHandler,
} from "express";

import { AuthVerifier, AuthenticationError } from "./auth";
import { AuthenticatedUser, NotificationRecord } from "./domain";
import { FirestorePackageService, PackageError } from "./package_service";
import {
  NotificationRepository,
  NotificationStorageNotConfiguredError,
} from "./notification_repository";
import {
  InvalidWorkflowEventError,
  NotificationNotFoundError,
  NotificationService,
} from "./notification_service";

export interface NotificationAppDependencies {
  authVerifier: AuthVerifier;
  notificationRepository: NotificationRepository;
  packageService?: FirestorePackageService;
}

export function createNotificationApp(
  dependencies: NotificationAppDependencies,
): express.Express {
  const app = express();
  const service = new NotificationService(
    dependencies.notificationRepository,
  );

  app.disable("x-powered-by");
  app.use(express.json({ limit: "32kb" }));
  app.use((_request, response, next) => {
    response.setHeader("Cache-Control", "no-store");
    next();
  });
  app.use(authenticate(dependencies.authVerifier));
  app.use(rejectRecipientOverrides);

  const packages = () => {
    if (!dependencies.packageService) throw new PackageError(503, "Package storage has not been configured yet.");
    return dependencies.packageService;
  };
  const client = (response: Response) => {
    const user = currentUser(response);
    if (user.role !== "client") throw new AuthenticationError("Package selection is available to clients only.", 403);
    return user.uid;
  };
  const admin = (response: Response) => {
    const user = currentUser(response);
    if (user.role !== "admin") throw new AuthenticationError("Administrator access is required.", 403);
    return user;
  };
  app.get("/admin/memberships/pending", asyncRoute(async (_request, response) => {
    admin(response);
    response.json({ data: { memberships: await packages().pendingMemberships() } });
  }));
  app.post("/admin/memberships/:id/verify-payment", asyncRoute(async (request, response) => {
    const actor = admin(response);
    const body = isObject(request.body) ? request.body : {};
    if (Object.keys(body).some(key => key !== "reference") || typeof body.reference !== "string") {
      throw new PackageError(400, "Only a verification reference may be supplied.");
    }
    const membership = await packages().verifyManually(actor, request.params.id ?? "", body.reference);
    response.json({ data: { membership } });
  }));
  app.get("/packages", asyncRoute(async (_request, response) => {
    response.json({ data: { packages: await packages().catalog() } });
  }));
  app.get("/memberships/me", asyncRoute(async (_request, response) => {
    response.json({ data: { memberships: await packages().memberships(client(response)) } });
  }));
  app.post("/memberships", asyncRoute(async (request, response) => {
    const uid = client(response);
    const body = isObject(request.body) ? request.body : {};
    if (Object.keys(body).some(key => !["package_id", "request_id"].includes(key)) || typeof body.package_id !== "string" || typeof body.request_id !== "string") {
      throw new PackageError(400, "Only package_id and request_id may be supplied.");
    }
    const membership = await packages().select(uid, body.package_id, body.request_id);
    response.json({ data: { membership } });
  }));

  app.get(
    "/notifications",
    asyncRoute(async (_request, response) => {
      const notifications = await service.list(currentUser(response));
      response.status(200).json({
        data: { notifications: notifications.map(toApiNotification) },
      });
    }),
  );

  app.get(
    "/notifications/:notificationId",
    asyncRoute(async (request, response) => {
      const notification = await service.get(
        currentUser(response),
        request.params.notificationId ?? "",
      );
      response.status(200).json({
        data: { notification: toApiNotification(notification) },
      });
    }),
  );

  app.patch(
    "/notifications/read-all",
    asyncRoute(async (_request, response) => {
      const updatedCount = await service.markAllRead(currentUser(response));
      response.status(200).json({ data: { updated_count: updatedCount } });
    }),
  );

  app.patch(
    "/notifications/:notificationId/read",
    asyncRoute(async (request, response) => {
      const notification = await service.markRead(
        currentUser(response),
        request.params.notificationId ?? "",
      );
      response.status(200).json({
        data: { notification: toApiNotification(notification) },
      });
    }),
  );

  app.use((_request, response) => {
    response.status(404).json({ error: "Endpoint not found." });
  });

  app.use(
    (
      error: unknown,
      _request: Request,
      response: Response,
      _next: NextFunction,
    ) => {
      if (error instanceof AuthenticationError) {
        response.status(error.statusCode).json({ error: error.message });
        return;
      }
      if (error instanceof PackageError) {
        response.status(error.statusCode).json({ error: error.message });
        return;
      }
      if (error instanceof NotificationNotFoundError) {
        response.status(404).json({ error: error.message });
        return;
      }
      if (error instanceof InvalidWorkflowEventError) {
        response.status(400).json({ error: error.message });
        return;
      }
      if (error instanceof NotificationStorageNotConfiguredError) {
        response.status(503).json({
          error: "Notification storage has not been configured yet.",
        });
        return;
      }

      console.error("Unhandled FitNEP API error", error);
      response.status(500).json({ error: "Internal server error." });
    },
  );

  return app;
}

function authenticate(authVerifier: AuthVerifier): RequestHandler {
  return asyncRoute(async (request, response, next) => {
    const authorization = request.header("authorization")?.trim();
    const match = authorization?.match(/^Bearer\s+(.+)$/i);
    if (match?.[1] === undefined || match[1].trim().length === 0) {
      throw new AuthenticationError("A Firebase ID token is required.");
    }
    response.locals.user = await authVerifier.verifyIdToken(match[1].trim());
    next();
  });
}

function rejectRecipientOverrides(
  request: Request,
  response: Response,
  next: NextFunction,
): void {
  const forbiddenKeys = ["recipient_id", "recipientId", "user_id", "userId"];
  const queryOverrides = forbiddenKeys.some((key) => request.query[key] != null);
  const body = isObject(request.body) ? request.body : {};
  const bodyOverrides = forbiddenKeys.some((key) => body[key] != null);

  if (queryOverrides || bodyOverrides) {
    response.status(400).json({
      error: "Recipient identity is derived from the authentication token.",
    });
    return;
  }
  next();
}

function currentUser(response: Response): AuthenticatedUser {
  return response.locals.user as AuthenticatedUser;
}

function toApiNotification(notification: NotificationRecord) {
  return {
    id: notification.id,
    recipient_id: notification.recipientId,
    title: notification.title,
    message: notification.message,
    type: notification.type,
    reference_id: notification.referenceId,
    is_read: notification.isRead,
    created_at: notification.createdAt,
  };
}

function asyncRoute(
  handler: (
    request: Request,
    response: Response,
    next: NextFunction,
  ) => Promise<void>,
): RequestHandler {
  return (request, response, next) => {
    void handler(request, response, next).catch(next);
  };
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
