import express, {
  NextFunction,
  Request,
  Response,
  RequestHandler,
} from "express";
import { randomUUID } from "node:crypto";

import { AuthVerifier, AuthenticationError } from "./auth";
import { AuditUnavailableError, AuditWriter } from "./audit";
import { PlatformSessionService, platformSessionHeader } from "./platform_sessions";
import { createSessionRouter } from "./session_routes";
import { roleCanPerformAction } from "./authorization_policy";
import {
  AuthenticatedUser,
  NotificationRecord,
  PackageChangeHistoryRecord,
  PackageHistoryValues,
  PurchaseRecord,
  StaffAccount,
} from "./domain";
import { FirestorePackageService, PackageError } from "./package_membership_service";
import {
  NotificationRepository,
  NotificationStorageNotConfiguredError,
} from "./notification_repository";
import {
  PrivacyPreferencesRepository,
  PrivacyPreferences,
  PrivacyPreferencesStorageNotConfiguredError,
  sharingChoices,
  sharingFields,
  UnconfiguredPrivacyPreferencesRepository,
} from "./privacy_preferences_repository";
import {
  InvalidPrivacyPreferencesError,
  PrivacyPreferencesAuthorizationError,
  PrivacyPreferencesService,
} from "./privacy_preferences_service";
import { PrivateRecordAuthorizationError } from "./nutrition_record_access_service";
import {
  PrivateRecordsError,
  PrivateRecordsStore,
  parseRecordCategory,
  parseRecordId,
  photoUploadOptions,
} from "./private_records";
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
import {
  StaffAccountError,
  StaffAccountRepository,
} from "./staff_account_repository";
import { StaffAccountService } from "./staff_account_service";
import {
  ClientAssignmentError,
  ClientAssignmentService,
} from "./client_assignment_service";

const temporaryPasswordPath = "/auth/staff/change-temporary-password";

export interface NotificationAppDependencies {
  authVerifier: AuthVerifier;
  notificationRepository: NotificationRepository;
  privacyPreferencesRepository?: PrivacyPreferencesRepository;
  privateRecordsStore?: PrivateRecordsStore;
  packageService?: FirestorePackageService;
  packageRepository?: PackageRepository;
  purchaseRepository?: PurchaseRepository;
  staffAccountRepository?: StaffAccountRepository;
  platformSessions?: PlatformSessionService;
  auditWriter?: AuditWriter;
  manualVerificationEnabled?: boolean;
  clientAssignmentService?: ClientAssignmentService;
  health?: {
    buildSha: string;
    checkReady(): Promise<void>;
  };
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
  const packageService = new PackageService(
    dependencies.packageRepository ?? new UnconfiguredPackageRepository(),
  );
  const purchaseService = new PurchaseService(
    dependencies.purchaseRepository ?? new UnconfiguredPurchaseRepository(),
  );
  const staffAccounts = new StaffAccountService(dependencies.staffAccountRepository);

  app.disable("x-powered-by");
  app.use((_request, response, next) => {
    response.setHeader("Cache-Control", "no-store");
    response.locals.correlationId = randomUUID();
    response.setHeader("X-Request-Id", response.locals.correlationId);
    next();
  });
  if (dependencies.health) {
    const health = dependencies.health;
    app.get("/healthz", asyncRoute(async (_request, response) => {
      try {
        if (!/^[a-f0-9]{40}$/i.test(health.buildSha)) throw new Error("Unknown backend build.");
        await health.checkReady();
        response.json({ data: { ready: true, build_sha: health.buildSha, node_version: process.version } });
      } catch {
        response.status(503).json({ data: { ready: false, build_sha: health.buildSha, node_version: process.version } });
      }
    }));
  }
  app.use(express.json({ limit: "32kb" }));
  if (dependencies.platformSessions) {
    app.use("/sessions", createSessionRouter(dependencies.authVerifier, dependencies.platformSessions));
  }

  app.use(authenticate(dependencies.authVerifier, dependencies.platformSessions));
  app.use(rejectRecipientOverrides);

  app.get(
    "/admin/staff-accounts",
    asyncRoute(async (request, response) => {
      const page = await staffAccounts.list(currentUser(response), request.query.cursor);
      response.json({
        data: {
          accounts: page.accounts.map(toApiStaffAccount),
          next_cursor: page.nextCursor,
        },
      });
    }),
  );

  app.post("/admin/staff-accounts", asyncRoute(async (request, response) => {
    const account = await staffAccounts.create(
      currentUser(response),
      isObject(request.body) ? request.body : {},
    );
    response.status(201).json({ data: { account: toApiStaffAccount(account) } });
  }));

  app.get("/admin/staff-accounts/history", asyncRoute(async (request, response) => {
    const page = await staffAccounts.listHistory(currentUser(response), request.query.cursor);
    response.json({ data: {
      entries: page.entries.map((entry) => ({
        id: entry.id,
        action: entry.action,
        actor_uid: entry.actorUid,
        actor_name: entry.actorName,
        before: entry.before && toApiStaffAccount(entry.before),
        after: toApiStaffAccount(entry.after),
        completed_at: entry.completedAt,
      })),
      next_cursor: page.nextCursor,
    } });
  }));

  app.patch("/admin/staff-accounts/:uid/active", asyncRoute(async (request, response) => {
    const account = await staffAccounts.setActive(
      currentUser(response),
      request.params.uid ?? "",
      isObject(request.body) ? request.body : {},
    );
    response.json({ data: { account: toApiStaffAccount(account) } });
  }));

  app.patch("/admin/staff-accounts/:uid", asyncRoute(async (request, response) => {
    const account = await staffAccounts.update(
      currentUser(response),
      request.params.uid ?? "",
      isObject(request.body) ? request.body : {},
    );
    response.json({ data: { account: toApiStaffAccount(account) } });
  }));

  app.post(temporaryPasswordPath, asyncRoute(async (request, response) => {
    await staffAccounts.changeTemporaryPassword(
      currentUser(response),
      isObject(request.body) ? request.body : {},
    );
    response.status(204).end();
  }));

  const clientAssignments = () => {
    if (!dependencies.clientAssignmentService) {
      throw new ClientAssignmentError(
        503,
        "Client assignment storage has not been configured yet.",
      );
    }
    return dependencies.clientAssignmentService;
  };
  app.get(
    "/admin/client-assignments/:clientId/eligibility",
    asyncRoute(async (request, response) => {
      const eligibility = await clientAssignments().eligibility(
        currentUser(response),
        request.params.clientId,
      );
      response.json({ data: { eligibility: {
        client_id: eligibility.clientId,
        package_status: eligibility.packageStatus,
        can_assign: eligibility.canAssign,
        message: eligibility.message,
      } } });
    }),
  );
  app.put(
    "/admin/client-assignments/:clientId",
    asyncRoute(async (request, response) => {
      const body = isObject(request.body) ? request.body : {};
      if (Object.keys(body).some(key => key !== "dietitian_id")) {
        throw new ClientAssignmentError(400, "Only dietitian_id may be supplied.");
      }
      const assignment = await clientAssignments().assign(
        currentUser(response),
        request.params.clientId,
        body.dietitian_id,
      );
      response.json({ data: { assignment: {
        client_id: assignment.clientId,
        dietitian_id: assignment.dietitianId,
        active: assignment.active,
        assigned_at: assignment.assignedAt,
      } } });
    }),
  );

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
  if (dependencies.manualVerificationEnabled !== false) app.post("/admin/memberships/:id/verify-payment", asyncRoute(async (request, response) => {
    const actor = admin(response);
    const body = isObject(request.body) ? request.body : {};
    if (Object.keys(body).some(key => key !== "reference") || typeof body.reference !== "string") {
      throw new PackageError(400, "Only a verification reference may be supplied.");
    }
    const membership = await packages().verifyManually(actor, request.params.id ?? "", body.reference);
    response.json({ data: { membership } });
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
      const preferences = await privacyPreferences.updateSharing(
        currentUser(response),
        request.body,
      );
      response.status(200).json({
        data: { preferences: toApiPrivacyPreferences(preferences) },
      });
    }),
  );

  const privateRecords = () => {
    if (!dependencies.privateRecordsStore) {
      throw new PrivateRecordsError(503, "Private record storage is temporarily unavailable.");
    }
    return dependencies.privateRecordsStore;
  };
  const recordPath = "/clients/:clientId/records/:category";
  app.get(recordPath, asyncRoute(async (request, response) => {
    const after = request.query.after;
    if (after !== undefined && typeof after !== "string") {
      throw new PrivateRecordsError(400, "Invalid record cursor.");
    }
    const records = await privateRecords().list(
      currentUser(response),
      parseRecordId(request.params.clientId),
      parseRecordCategory(request.params.category),
      after === undefined ? undefined : parseRecordId(after),
    );
    response.json({ data: { records, next_cursor: records.length === 50 ? records.at(-1)?.id : null } });
  }));
  app.post(recordPath, express.raw(photoUploadOptions), asyncRoute(async (request, response) => {
    const record = await privateRecords().collect(
      currentUser(response),
      parseRecordId(request.params.clientId),
      parseRecordCategory(request.params.category),
      request.body,
    );
    response.status(201).json({ data: { record } });
  }));
  app.get(`${recordPath}/:recordId/photo`, asyncRoute(async (request, response) => {
    const photo = await privateRecords().readPhoto(
      currentUser(response),
      parseRecordId(request.params.clientId),
      parseRecordCategory(request.params.category),
      parseRecordId(request.params.recordId),
    );
    response.set("X-Content-Type-Options", "nosniff");
    response.type(photo.contentType).send(photo.bytes);
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

  // â”€â”€ Customer-facing: returns only active packages â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  app.get(
    "/packages",
    asyncRoute(async (_request, response) => {
      if (!roleCanPerformAction(currentUser(response).role, "viewPackageCatalog")) {
        throw new AuthenticationError("This account cannot view the package catalog.", 403);
      }
      if (dependencies.packageRepository === undefined) {
        response.json({ data: { packages: await packages().catalog() } });
        return;
      }
      const activePackages = await packageService.list();
      response.status(200).json({
        data: { packages: activePackages.map(toApiPackage) },
      });
    }),
  );

  // â”€â”€ Admin: returns all packages including inactive â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

  // â”€â”€ Admin: edit a package â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

  // â”€â”€ Admin: activate or deactivate a package â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
      if (Object.keys(body).some(key => !["package_id", "request_id"].includes(key))) {
        throw new InvalidPurchaseError("Only package_id and request_id may be supplied.");
      }
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

  app.use((error: unknown, request: Request, response: Response, next: NextFunction) => {
    const denied = error instanceof PrivacyPreferencesAuthorizationError ||
      error instanceof PrivateRecordAuthorizationError || error instanceof PackageAuthorizationError ||
      error instanceof PurchaseAuthorizationError ||
      (error instanceof AuthenticationError && (error.statusCode === 401 || error.statusCode === 403)) ||
      (error instanceof PackageError && error.statusCode === 403);
    if (!denied || !dependencies.auditWriter || !response.locals.user) { next(error); return; }
    // Route templates contain no query values, tokens, proof bytes or medical answers.
    const route = typeof request.route?.path === "string" ? request.route.path : "protected-api";
    void dependencies.auditWriter.append({
      actor: currentUser(response), action: "access.denied",
      targetType: "api", targetId: request.method + " " + route,
      outcome: "denied", correlationId: response.locals.correlationId,
    }).then(() => next(error), () => next(new AuditUnavailableError()));
  });

  app.use(
    (
      error: unknown,
      _request: Request,
      response: Response,
      _next: NextFunction,
    ) => {
      if (error instanceof AuditUnavailableError) {
        response.status(503).json({ error: error.message });
        return;
      }
      if (error instanceof AuthenticationError) {
        response.status(error.statusCode).json({ error: error.message });
        return;
      }
      if (error instanceof StaffAccountError) {
        response.status(error.status).json({ error: error.message });
        return;
      }
      if (error instanceof ClientAssignmentError) {
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
      if (error instanceof PrivateRecordAuthorizationError) {
        response.status(403).json({ error: error.message });
        return;
      }
      if (error instanceof PrivateRecordsError) {
        response.status(error.status).json({ error: error.message });
        return;
      }
      if (isObject(error) && error.type === "entity.too.large") {
        response.status(413).json({ error: "The submitted data is too large." });
        return;
      }
      if (isObject(error) && error.type === "entity.parse.failed") {
        response.status(400).json({ error: "Invalid request body." });
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

      console.error("Unhandled FitNEP API error", {
        correlation_id: response.locals.correlationId,
        error_type: error instanceof Error ? error.name : "UnknownError",
      });
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
    ...(purchase.status === undefined ? {} : { status: purchase.status }),
    ...(purchase.daysRemaining === undefined ? {} : { days_remaining: purchase.daysRemaining }),
    ...(purchase.durationDays === undefined ? {} : { duration_days: purchase.durationDays }),
  };
}

function toApiStaffAccount(account: StaffAccount) {
  return {
    uid: account.uid,
    name: account.name,
    email: account.email,
    role: account.role,
    is_active: account.isActive,
  };
}

function authenticate(authVerifier: AuthVerifier, sessions?: PlatformSessionService): RequestHandler {
  return asyncRoute(async (request, response, next) => {
    const authorization = request.header("authorization")?.trim();
    const match = authorization?.match(/^Bearer\s+(.+)$/i);
    if (match?.[1] === undefined || match[1].trim().length === 0) {
      throw new AuthenticationError("A Firebase ID token is required.");
    }
    const user = await authVerifier.verifyIdToken(match[1].trim());
    response.locals.user = user;
    const changingTemporaryPassword = user.mustChangePassword === true &&
      request.method === "POST" && request.path === temporaryPasswordPath;
    if (user.mustChangePassword && !changingTemporaryPassword) {
      throw new AuthenticationError("Change your temporary password before continuing.", 403);
    }
    if (sessions && !changingTemporaryPassword) {
      await sessions.verify(user, request.header(platformSessionHeader));
    }
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

function toApiPrivacyPreferences(preferences: PrivacyPreferences) {
  const result: Record<string, boolean | string | null> = {
    updated_at: preferences.updatedAt,
  };
  for (const choice of sharingChoices) {
    result[sharingFields[choice]] = preferences[choice];
  }
  return result;
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
