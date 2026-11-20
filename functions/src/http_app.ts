import express, {
  NextFunction,
  Request,
  Response,
  RequestHandler,
} from "express";

import { AuthVerifier, AuthenticationError } from "./auth";
import {
  AuthenticatedUser,
  NotificationRecord,
  PackageChangeHistoryRecord,
  PackageHistoryValues,
  PurchaseRecord,
} from "./domain";
import {
  NotificationRepository,
  NotificationStorageNotConfiguredError,
} from "./notification_repository";
import {
  InvalidWorkflowEventError,
  NotificationNotFoundError,
  NotificationService,
} from "./notification_service";
import {
  PackageNotFoundError,
  PackageRepository,
  PackageRequestConflictError,
  PackageStorageNotConfiguredError,
  UnconfiguredPackageRepository,
} from "./package_repository";
import {
  InvalidPackageError,
  PackageAuthorizationError,
  PackageService,
} from "./package_service";
import {
  PurchasablePackageNotFoundError,
  PurchaseRepository,
  PurchaseRequestConflictError,
  PurchaseStorageNotConfiguredError,
  UnconfiguredPurchaseRepository,
} from "./purchase_repository";
import {
  InvalidPurchaseError,
  PurchaseAuthorizationError,
  PurchaseService,
} from "./purchase_service";

export interface NotificationAppDependencies {
  authVerifier: AuthVerifier;
  notificationRepository: NotificationRepository;
  packageRepository?: PackageRepository;
  purchaseRepository?: PurchaseRepository;
}

export function createNotificationApp(
  dependencies: NotificationAppDependencies,
): express.Express {
  const app = express();
  const service = new NotificationService(
    dependencies.notificationRepository,
  );
  const packageService = new PackageService(
    dependencies.packageRepository ?? new UnconfiguredPackageRepository(),
  );
  const purchaseService = new PurchaseService(
    dependencies.purchaseRepository ?? new UnconfiguredPurchaseRepository(),
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

  // ── Customer-facing: returns only active packages ──────────────────────────
  app.get(
    "/packages",
    asyncRoute(async (_request, response) => {
      const packages = await packageService.list();
      response.status(200).json({
        data: { packages: packages.map(toApiPackage) },
      });
    }),
  );

  // ── Admin: returns all packages including inactive ─────────────────────────
  app.get(
    "/admin/packages",
    asyncRoute(async (_request, response) => {
      const user = currentUser(response);
      if (user.role !== "admin") {
        throw new PackageAuthorizationError();
      }
      const packages = await packageService.listAll();
      response.status(200).json({
        data: { packages: packages.map(toApiPackage) },
      });
    }),
  );

  app.get(
    "/admin/package-history",
    asyncRoute(async (_request, response) => {
      const history = await packageService.listHistory(currentUser(response));
      response.status(200).json({
        data: { history: history.map(toApiPackageHistory) },
      });
    }),
  );

  app.post(
    "/packages",
    asyncRoute(async (request, response) => {
      const body = isObject(request.body) ? request.body : {};
      const created = await packageService.create(currentUser(response), {
        name: body.name,
        durationMonths: body.duration_months,
        price: body.price,
        featureDescription: body.feature_description,
        requestId: body.request_id,
      });
      response.status(201).json({ data: { package: toApiPackage(created) } });
    }),
  );

  // ── Admin: edit a package ──────────────────────────────────────────────────
  app.patch(
    "/packages/:packageId",
    asyncRoute(async (request, response) => {
      const body = isObject(request.body) ? request.body : {};
      const updated = await packageService.update(
        currentUser(response),
        request.params.packageId ?? "",
        {
          name: body.name,
          durationMonths: body.duration_months,
          price: body.price,
          featureDescription: body.feature_description,
        },
      );
      response.status(200).json({ data: { package: toApiPackage(updated) } });
    }),
  );

  // ── Admin: activate or deactivate a package ────────────────────────────────
  app.patch(
    "/packages/:packageId/active",
    asyncRoute(async (request, response) => {
      const body = isObject(request.body) ? request.body : {};
      const isActive = body.is_active;
      if (typeof isActive !== "boolean") {
        response.status(400).json({ error: "is_active must be a boolean." });
        return;
      }
      const updated = await packageService.setActiveStatus(
        currentUser(response),
        request.params.packageId ?? "",
        isActive,
      );
      response.status(200).json({ data: { package: toApiPackage(updated) } });
    }),
  );

  app.get(
    "/purchases/current",
    asyncRoute(async (_request, response) => {
      const purchase = await purchaseService.getCurrent(currentUser(response));
      response.status(200).json({
        data: { purchase: purchase === null ? null : toApiPurchase(purchase) },
      });
    }),
  );

  app.post(
    "/purchases",
    asyncRoute(async (request, response) => {
      const body = isObject(request.body) ? request.body : {};
      const purchase = await purchaseService.create(currentUser(response), {
        packageId: body.package_id,
        requestId: body.request_id,
      });
      response.status(201).json({
        data: { purchase: toApiPurchase(purchase) },
      });
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
      if (error instanceof PackageAuthorizationError) {
        response.status(403).json({ error: error.message });
        return;
      }
      if (error instanceof InvalidPackageError) {
        response.status(400).json({ error: error.message });
        return;
      }
      if (error instanceof PackageRequestConflictError) {
        response.status(409).json({ error: error.message });
        return;
      }
      if (error instanceof PackageNotFoundError) {
        response.status(404).json({ error: error.message });
        return;
      }
      if (error instanceof PackageStorageNotConfiguredError) {
        response.status(503).json({
          error: "Package storage has not been configured yet.",
        });
        return;
      }
      if (error instanceof PurchaseAuthorizationError) {
        response.status(403).json({ error: error.message });
        return;
      }
      if (error instanceof InvalidPurchaseError) {
        response.status(400).json({ error: error.message });
        return;
      }
      if (error instanceof PurchaseRequestConflictError) {
        response.status(409).json({ error: error.message });
        return;
      }
      if (error instanceof PurchasablePackageNotFoundError) {
        response.status(404).json({ error: error.message });
        return;
      }
      if (error instanceof PurchaseStorageNotConfiguredError) {
        response.status(503).json({
          error: "Purchase storage has not been configured yet.",
        });
        return;
      }

      console.error("Unhandled notification API error", error);
      response.status(500).json({ error: "Internal server error." });
    },
  );

  return app;
}

function toApiPackage(packageRecord: import("./domain").PackageRecord) {
  return {
    id: packageRecord.id,
    name: packageRecord.name,
    duration_months: packageRecord.durationMonths,
    price: packageRecord.price,
    feature_description: packageRecord.featureDescription,
    is_active: packageRecord.isActive,
    created_at: packageRecord.createdAt,
  };
}

function toApiPackageHistory(history: PackageChangeHistoryRecord) {
  return {
    id: history.id,
    package_id: history.packageId,
    package_name: history.packageName,
    admin_id: history.adminId,
    admin_name: history.adminName,
    action: history.action,
    previous_values: history.previousValues === null
      ? null
      : toApiHistoryValues(history.previousValues),
    new_values: toApiHistoryValues(history.newValues),
    changed_at: history.changedAt,
  };
}

function toApiHistoryValues(values: PackageHistoryValues) {
  return {
    ...(values.name === undefined ? {} : { name: values.name }),
    ...(values.durationMonths === undefined
      ? {}
      : { duration_months: values.durationMonths }),
    ...(values.price === undefined ? {} : { price: values.price }),
    ...(values.featureDescription === undefined
      ? {}
      : { feature_description: values.featureDescription }),
    ...(values.isActive === undefined
      ? {}
      : { is_active: values.isActive }),
  };
}

function toApiPurchase(purchase: PurchaseRecord) {
  return {
    id: purchase.id,
    package_id: purchase.packageId,
    package_name: purchase.packageName,
    price_paid: purchase.pricePaid,
    duration_months: purchase.durationMonths,
    feature_description: purchase.featureDescription,
    purchased_at: purchase.purchasedAt,
    expires_at: purchase.expiresAt,
  };
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
