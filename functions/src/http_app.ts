import express, {
  NextFunction,
  Request,
  Response,
  RequestHandler,
} from "express";

import { AuthVerifier, AuthenticationError } from "./auth";
import { AuthenticatedUser, NotificationRecord } from "./domain";
import {
  NotificationRepository,
  NotificationStorageNotConfiguredError,
} from "./notification_repository";
import {
  PrivacyPreferencesRepository,
  PrivacyPreferencesStorageNotConfiguredError,
  UnconfiguredPrivacyPreferencesRepository,
} from "./privacy_preferences_repository";
import {
  InvalidPrivacyPreferencesError,
  PrivacyPreferencesAuthorizationError,
  PrivacyPreferencesService,
} from "./privacy_preferences_service";
import {
  AssignmentStorageNotConfiguredError,
  NutritionRecordsAuthorizationError,
} from "./nutrition_record_access_service";
import {
  InvalidWorkflowEventError,
  NotificationNotFoundError,
  NotificationService,
} from "./notification_service";

export interface NotificationAppDependencies {
  authVerifier: AuthVerifier;
  notificationRepository: NotificationRepository;
  privacyPreferencesRepository?: PrivacyPreferencesRepository;
}

export function createNotificationApp(
  dependencies: NotificationAppDependencies,
): express.Express {
  const app = express();
  const service = new NotificationService(
    dependencies.notificationRepository,
  );
  const privacyPreferences = new PrivacyPreferencesService(
    dependencies.privacyPreferencesRepository ??
      new UnconfiguredPrivacyPreferencesRepository(),
  );

  app.disable("x-powered-by");
  app.use(express.json({ limit: "32kb" }));
  app.use((_request, response, next) => {
    response.setHeader("Cache-Control", "no-store");
    next();
  });
  app.use(authenticate(dependencies.authVerifier));
  app.use(rejectRecipientOverrides);

  app.get(
    "/privacy/preferences",
    asyncRoute(async (_request, response) => {
      const preferences = await privacyPreferences.getForUser(
        currentUser(response),
      );
      response.status(200).json({
        data: { preferences: toApiPrivacyPreferences(preferences) },
      });
    }),
  );

  app.patch(
    "/privacy/preferences",
    asyncRoute(async (request, response) => {
      const enabled = requestedNutritionSharing(request.body);
      const preferences = await privacyPreferences.setNutritionSharing(
        currentUser(response),
        enabled,
      );
      response.status(200).json({
        data: { preferences: toApiPrivacyPreferences(preferences) },
      });
    }),
  );

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
      if (error instanceof PrivacyPreferencesAuthorizationError) {
        response.status(403).json({ error: error.message });
        return;
      }
      if (error instanceof InvalidPrivacyPreferencesError) {
        response.status(400).json({ error: error.message });
        return;
      }
      if (error instanceof PrivacyPreferencesStorageNotConfiguredError) {
        response.status(503).json({
          error: "Privacy preferences storage has not been configured yet.",
        });
        return;
      }
      if (error instanceof NutritionRecordsAuthorizationError) {
        response.status(403).json({ error: error.message });
        return;
      }
      if (error instanceof AssignmentStorageNotConfiguredError) {
        response.status(503).json({
          error: "Client assignment storage has not been configured yet.",
        });
        return;
      }

      console.error("Unhandled notification API error", error);
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

function toApiPrivacyPreferences(preferences: {
  shareNutritionRecords: boolean;
  updatedAt: string | null;
}) {
  return {
    share_nutrition_records: preferences.shareNutritionRecords,
    updated_at: preferences.updatedAt,
  };
}

function requestedNutritionSharing(body: unknown): unknown {
  if (
    !isObject(body) ||
    Object.keys(body).length !== 1 ||
    !Object.hasOwn(body, "share_nutrition_records")
  ) {
    throw new InvalidPrivacyPreferencesError();
  }
  return body.share_nutrition_records;
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
