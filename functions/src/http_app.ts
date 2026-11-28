import express, {
  NextFunction,
  Request,
  Response,
  RequestHandler,
} from "express";

import { randomUUID } from "node:crypto";
import { HttpsError } from "firebase-functions/v2/https";
import { GooglePasswordService } from "./google_password_service";
import { ClientAssignmentError, ClientAssignmentService } from "./client_assignment_service";
import { AuditUnavailableError, AuditWriter } from "./audit";
import { healthAuditTarget } from "./audited_health_reads";
import { PlatformSessionService, platformSessionHeader } from "./platform_sessions";
import { createSessionRouter } from "./session_routes";
import { StaffAccountService } from "./staff_account_service";
import { StaffAccountError, StaffAccountRepository } from "./staff_account_repository";
import { StaffAccount } from "./domain";
import { AuthVerifier, AuthenticationError } from "./auth";
import { AccountInputError, FirestoreAccountService, FirestoreAuditStore } from "./account_service";
import { PermissionDeniedError, requirePermission } from "./authorization_policy";
import { endpointAccess } from "./endpoint_access";
import { BackendUnavailableError, createRbacRouter } from "./rbac_http";
import {
  AuthenticatedUser,
  NotificationRecord,
  PackageChangeHistoryRecord,
  PackageHistoryValues,
  PurchaseRecord,
} from "./domain";
import { FirestorePackageService, PackageError } from "./package_membership_service";
import { CheckoutPayments } from "./checkout_payments";
import { onboardingReady } from "./onboarding";
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
  ClientIntakeError,
  IntakeWorkspace,
  ClientIntakeRecord,
  ClientIntakeService,
} from "./client_intake_service";
const temporaryPasswordPath = "/auth/staff/change-temporary-password";

export interface NotificationAppDependencies {
  recoverCommittedEvents?: () => void;
  googlePasswordService?: GooglePasswordService;
  clientAssignmentService?: ClientAssignmentService;
  staffAccountRepository?: StaffAccountRepository;
  platformSessions?: PlatformSessionService;
  auditWriter?: AuditWriter;
  manualVerificationEnabled?: boolean;
  health?: { buildSha: string; checkReady(): Promise<void> };
  accounts?: FirestoreAccountService;
  audit?: FirestoreAuditStore;
  authVerifier: AuthVerifier;
  notificationRepository: NotificationRepository;
  privacyPreferencesRepository?: PrivacyPreferencesRepository;
  privateRecordsStore?: PrivateRecordsStore;
  packageService?: FirestorePackageService;
  checkoutPayments?: CheckoutPayments;
  packageRepository?: PackageRepository;
  purchaseRepository?: PurchaseRepository;
  clientIntakeService?: ClientIntakeService;
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
  if (dependencies.recoverCommittedEvents) app.use((_request, response, next) => {
    response.once("finish", dependencies.recoverCommittedEvents!);
    next();
  });
  const json = express.json({ limit: "32kb" });
  app.use((request, response, next) => {
    if (request.method === "POST" && /^\/payments\/[^/]+\/proof\/?$/i.test(request.path)) next();
    else json(request, response, next);
  });
  app.use((_request, response, next) => {
    response.setHeader("Cache-Control", "no-store");
    next();
  });

  app.use((_request, response, next) => {
    response.locals.correlationId = randomUUID();
    response.setHeader("X-Request-Id", response.locals.correlationId);
    next();
  });
  if (dependencies.health) {
    const health = dependencies.health;
    app.get("/healthz", asyncRoute(async (_request, response) => {
      try {
        if (!/^[a-f0-9]{40}$/i.test(health.buildSha)) throw new Error();
        await health.checkReady();
        response.json({ data: { ready: true, build_sha: health.buildSha, node_version: process.version } });
      } catch {
        response.status(503).json({ data: { ready: false, build_sha: health.buildSha, node_version: process.version } });
      }
    }));
  }
  if (dependencies.platformSessions) app.use("/sessions", createSessionRouter(dependencies.authVerifier, dependencies.platformSessions));
  app.use(authenticate(dependencies.authVerifier));
  app.use(asyncRoute(async (request, response, next) => {
    const prerequisites = ["/session", "/auth/staff/change-temporary-password"];
    if (response.locals.user.mustChangePassword === true && !prerequisites.includes(request.path)) {
      throw new AuthenticationError("Change your temporary password before continuing.", 403);
    }
    if (dependencies.platformSessions && !prerequisites.includes(request.path)) {
      await dependencies.platformSessions.verify(currentUser(response), request.header(platformSessionHeader));
    }
    next();
  }));
  app.use(asyncRoute(async (request, response, next) => {
    const access = endpointAccess(request.method, request.path) ??
      (/^\/admin(?:\/|$)/i.test(request.path) ? { permission: "manage_user_roles" as const, resource: "admin_features" } : null);
    response.locals.access = access;
    if (access) {
      const user = currentUser(response);
      requirePermission(user.role, access.permission, user.permissions?.auditRead, user.permissions?.paymentsVerify);
      if (user.emailVerified === false &&
          !["view_dashboard", "view_own_profile", "edit_own_profile"].includes(access.permission)) {
        throw new PermissionDeniedError("Email verification is required.");
      }
    }
    next();
  }));
  const checkout = () => {
    if (!dependencies.checkoutPayments) throw new PackageError(503, "Checkout is temporarily unavailable.");
    return dependencies.checkoutPayments;
  };
  app.get("/payments/checkout", asyncRoute(async (request, response) => {
    response.json({ data: { checkout: await checkout().checkout(currentUser(response), request.query.membership_id) } });
  }));
  app.get("/payments/me", asyncRoute(async (_request, response) => {
    response.json({ data: { payments: await checkout().listOwn(currentUser(response)) } });
  }));
  app.get("/payments/:id/proof", asyncRoute(async (request, response) => {
    const proof = await checkout().proof(currentUser(response), request.params.id!);
    response.set("X-Content-Type-Options", "nosniff").type(proof.contentType).send(proof.bytes);
  }));
  app.post("/payments/:id/proof", express.json({ limit: "700kb" }), asyncRoute(async (request, response) => {
    const payment = await checkout().submit(currentUser(response), request.params.id!, request.body, response.locals.correlationId);
    response.json({ data: { payment } });
  }));
  app.get("/payments/:id", asyncRoute(async (request, response, next) => {
    const detail = await dependencies.checkoutPayments?.detail(currentUser(response), request.params.id!);
    if (detail) response.json({ data: detail });
    else next(); // Existing payment notifications still use the generic workflow record route.
  }));
  app.get("/admin/payments", asyncRoute(async (request, response) => {
    response.json({ data: { payments: await checkout().listReview(currentUser(response), request.query.status) } });
  }));
  app.get("/admin/payments/:id", asyncRoute(async (request, response) => {
    const detail = await checkout().detail(currentUser(response), request.params.id!, true);
    if (!detail) throw new PackageError(404, "Payment not found.");
    response.json({ data: detail });
  }));
  for (const [action, status] of [["verify", "verified"], ["reject", "rejected"]] as const) {
    app.post(`/admin/payments/:id/${action}`, asyncRoute(async (request, response) => {
      const data = await checkout().decide(currentUser(response), request.params.id!, status, request.body, response.locals.correlationId);
      response.json({ data });
    }));
  }
  app.post("/admin/payments/:id/adjustments", asyncRoute(async (request, response) => {
    const adjustment = await checkout().adjust(currentUser(response), request.params.id!, request.body, response.locals.correlationId);
    response.json({ data: { adjustment } });
  }));
  app.use(createRbacRouter(dependencies.accounts, dependencies.audit, dependencies.privateRecordsStore, dependencies.checkoutPayments));
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

  app.post("/auth/staff/change-temporary-password", asyncRoute(async (request, response) => {
    if (currentUser(response).googleTemporaryPassword === true) {
      if (!dependencies.googlePasswordService) throw new StaffAccountError(503, "Password setup is unavailable.");
      if (!isObject(request.body) || Object.keys(request.body).some(key => key !== "new_password")) {
        throw new StaffAccountError(400, "Supply only a new password.");
      }
      try {
        await dependencies.googlePasswordService.change(currentUser(response), request.body.new_password);
      } catch (error) {
        if (error instanceof HttpsError) {
          const status = error.code === "invalid-argument" ? 400 : error.code === "permission-denied" ? 403 : error.code === "failed-precondition" ? 409 : 503;
          throw new StaffAccountError(status, error.message);
        }
        throw error;
      }
      response.status(204).end();
      return;
    }
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
    "/admin/client-assignments/dietitian-counts",
    asyncRoute(async (_request, response) => {
      const counts = await clientAssignments().dietitianClientCounts(
        currentUser(response),
      );
      response.json({ data: { counts } });
    }),
  );
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
        response.locals.correlationId,
      );
      response.json({ data: { assignment: {
        client_id: assignment.clientId,
        dietitian_id: assignment.dietitianId,
        active: assignment.active,
        assigned_at: assignment.assignedAt,
      } } });
    }),
  );

  // ── Dietitian: view an assigned client ─────────────────────────────────────
  app.get(
    "/dietitian/assigned-clients/:clientId",
    asyncRoute(async (request, response) => {
      const profile = await clientAssignments().assignedClient(
        currentUser(response),
        request.params.clientId,
      );
      response.json({ data: { client: {
        id: profile.id,
        name: profile.name,
        email: profile.email,
        assignment_status: profile.assignmentStatus,
        assigned_at: profile.assignedAt,
      } } });
    }),
  );
  app.get(
    "/dietitian/assigned-clients/:clientId/intake",
    asyncRoute(async (request, response) => {
      if (!dependencies.clientIntakeService) {
        throw new ClientIntakeError(
          503,
          "Client intake storage has not been configured yet.",
        );
      }
      const intake = await dependencies.clientIntakeService
        .getAssignedClientIntake(
          currentUser(response),
          request.params.clientId,
          response.locals.correlationId,
        );
      response.json({ data: { intake: toApiClientIntake(intake) } });
    }),
  );
  app.patch(
    "/dietitian/assigned-clients/:clientId/intake/review",
    asyncRoute(async (request, response) => {
      if (!dependencies.clientIntakeService) {
        throw new ClientIntakeError(
          503,
          "Client intake storage has not been configured yet.",
        );
      }
      const intake = await dependencies.clientIntakeService
        .updateAssignedClientIntakeReview(
          currentUser(response),
          request.params.clientId,
          request.body,
          response.locals.correlationId,
        );
      response.json({ data: { intake: toApiClientIntake(intake) } });
    }),
  );
  const clientIntake = () => {
    if (!dependencies.clientIntakeService) throw new ClientIntakeError(503, "Intake storage is unavailable.");
    return dependencies.clientIntakeService;
  };
  app.get("/intakes/me", asyncRoute(async (_request, response) => {
    const intake = await clientIntake().getOwnIntake(currentUser(response), response.locals.correlationId);
    response.json({ data: { intake: toApiClientIntake(intake) } });
  }));
  app.get("/intakes/me/draft", asyncRoute(async (_request, response) => {
    const workspace = await clientIntake().getOwnWorkspace(currentUser(response), response.locals.correlationId);
    response.json({ data: toApiIntakeWorkspace(workspace) });
  }));
  app.put("/intakes/me/draft", asyncRoute(async (request, response) => {
    const workspace = await clientIntake().saveOwnDraft(
      currentUser(response), request.body, response.locals.correlationId,
    );
    response.json({ data: toApiIntakeWorkspace(workspace) });
  }));
  app.post("/intakes/me/submit", asyncRoute(async (request, response) => {
    const workspace = await clientIntake().submitOwnIntake(
      currentUser(response), request.body, response.locals.correlationId,
    );
    response.json({ data: toApiIntakeWorkspace(workspace) });
  }));
  const getSubmittedIntake = asyncRoute(async (request, response) => {
    const intake = await clientIntake().getSubmittedIntake(
      currentUser(response), request.params.clientId, response.locals.correlationId, request.params.version,
    );
    response.json({ data: { intake: toApiClientIntake(intake) } });
  });
  app.get("/clients/:clientId/intake", getSubmittedIntake);
  app.get("/clients/:clientId/intake/versions", asyncRoute(async (request, response) => {
    const index = await clientIntake().listSubmittedVersions(
      currentUser(response), request.params.clientId, response.locals.correlationId, request.query.before,
    );
    response.json({ data: {
      client_id: request.params.clientId,
      versions: index.versions.map(item => ({ version: item.version, submitted_at: item.submittedAt })),
      next_before: index.nextBefore,
    } });
  }));
  app.get("/clients/:clientId/intake/versions/:version", getSubmittedIntake);

  const packages = () => {
    if (!dependencies.packageService) throw new PackageError(503, "Package storage has not been configured yet.");
    return dependencies.packageService;
  };
  const client = (response: Response) => {
    const user = currentUser(response);
    requirePermission(user.role, "manage_own_membership");
    return user.uid;
  };
  const admin = (response: Response) => {
    const user = currentUser(response);
    requirePermission(user.role, "manage_business_settings");
    return user;
  };
  app.get("/admin/memberships/pending", asyncRoute(async (_request, response) => {
    admin(response);
    response.json({ data: { memberships: await packages().pendingMemberships() } });
  }));
  if (dependencies.manualVerificationEnabled === true) app.post("/admin/memberships/:id/verify-payment", asyncRoute(async (request, response) => {
    const actor = admin(response);
    const body = isObject(request.body) ? request.body : {};
    if (Object.keys(body).some(key => key !== "reference") || typeof body.reference !== "string") {
      throw new PackageError(400, "Only a verification reference may be supplied.");
    }
    const membership = await packages().verifyManually(actor, request.params.id ?? "", body.reference);
    response.json({ data: { membership } });
  }));
  app.get("/memberships/me", asyncRoute(async (_request, response) => {
    response.json({ data: { memberships: await packages().membershipsWithLegacy(client(response)) } });
  }));
  app.post("/memberships", asyncRoute(async (request, response) => {
    const uid = client(response);
    const body = isObject(request.body) ? request.body : {};
    if (Object.keys(body).some(key => !["package_id", "request_id", "expected_client_id"].includes(key)) || typeof body.package_id !== "string" || typeof body.request_id !== "string") {
      throw new PackageError(400, "A package ID and request ID are required.");
    }
    if (body.expected_client_id !== undefined && uid !== body.expected_client_id) throw new PermissionDeniedError();
    await requireOnboarding(uid);
    const membership = await packages().select(uid, body.package_id, body.request_id, currentUser(response), response.locals.correlationId);
    response.json({ data: { membership } });
  }));
  const requireOnboarding = async (uid: string) => {
    // Production and demo both provide the account store; HTTP-only test adapters may omit it.
    if (!dependencies.accounts) return;
    const profile = await dependencies.accounts.firestore.doc(`users/${uid}`).get();
    if (!onboardingReady(profile.get("onboarding"))) throw new PackageError(409, "Complete or skip onboarding before choosing a package.");
  };

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
  const recordTarget = (request: Request, response: Response) => {
    const target = {
      clientId: parseRecordId(request.params.clientId),
      category: parseRecordCategory(request.params.category),
      recordId: request.params.recordId === undefined ? undefined : parseRecordId(request.params.recordId),
    };
    // Express restores route params before its error middleware runs.
    response.locals.healthAuditTarget = healthAuditTarget(target);
    return target;
  };
  app.get(recordPath, asyncRoute(async (request, response) => {
    const target = recordTarget(request, response);
    const after = request.query.after;
    if (after !== undefined && typeof after !== "string") {
      throw new PrivateRecordsError(400, "Invalid record cursor.");
    }
    const records = await privateRecords().list(
      currentUser(response),
      target.clientId,
      target.category,
      after === undefined ? undefined : parseRecordId(after),
      response.locals.correlationId,
    );
    response.json({ data: { records, next_cursor: records.length === 50 ? records.at(-1)?.id : null } });
  }));
  app.post(recordPath, express.raw(photoUploadOptions), asyncRoute(async (request, response) => {
    const target = recordTarget(request, response);
    const record = await privateRecords().collect(
      currentUser(response),
      target.clientId,
      target.category,
      request.body,
    );
    response.status(201).json({ data: { record } });
  }));
  app.get(`${recordPath}/:recordId/photo`, asyncRoute(async (request, response) => {
    const target = recordTarget(request, response);
    const photo = await privateRecords().readPhoto(
      currentUser(response),
      target.clientId,
      target.category,
      target.recordId!,
      response.locals.correlationId,
    );
    response.set("X-Content-Type-Options", "nosniff");
    response.type(photo.contentType).send(photo.bytes);
  }));
  app.get(`${recordPath}/:recordId`, asyncRoute(async (request, response) => {
    const target = recordTarget(request, response);
    const record = await privateRecords().read(currentUser(response),
      target.clientId, target.category, target.recordId!, response.locals.correlationId);
    response.json({ data: { record } });
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
      requirePermission(user.role, "manage_business_settings");
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
      await requireOnboarding(currentUser(response).uid);
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
      request: Request,
      response: Response,
      _next: NextFunction,
    ) => {
      if (error instanceof AuthenticationError && error.statusCode === 401 && response.locals.user && dependencies.auditWriter) {
        void dependencies.auditWriter.append({ actor: response.locals.user, action: "access.denied", targetType: "api",
          targetId: "protected_endpoint", outcome: "denied", correlationId: response.locals.correlationId }).then(() => {
            response.status(401).json({ code: error.code, error: "Your session has ended. Sign in again." });
          }, () => { response.status(503).json({ code: "unavailable", error: "Audit services are unavailable." }); });
        return;
      }
      const denied = error instanceof PermissionDeniedError ||
        error instanceof AuthenticationError && error.statusCode === 403 ||
        error instanceof PackageError && error.statusCode === 403 ||
        error instanceof PrivacyPreferencesAuthorizationError ||
        error instanceof PrivateRecordAuthorizationError ||
        error instanceof PackageAuthorizationError || error instanceof PurchaseAuthorizationError ||
        error instanceof StaffAccountError && error.status === 403 ||
        error instanceof ClientAssignmentError && error.statusCode === 403;
      if (denied) {
        const user = response.locals.user as AuthenticatedUser | undefined;
        const identity = error instanceof AuthenticationError ? error.identity : undefined;
        const access = response.locals.access ?? endpointAccess(request.method, request.path);
        const attempt = { uid: user?.uid ?? identity?.uid ?? null, role: user?.role ?? identity?.role ?? null,
          action: access?.permission ?? "access_protected_feature", resource: access?.resource ?? "protected_endpoint",
          recordId: access?.recordId ?? null,
          reason: error instanceof PermissionDeniedError ? error.reason : "Authorization denied." };
        const target = error instanceof PrivateRecordAuthorizationError && response.locals.healthAuditTarget
          ? response.locals.healthAuditTarget
          : { targetType: "api" as const, targetId: access?.resource ?? "protected_endpoint" };
        void Promise.all([
          dependencies.audit?.denied(attempt, !dependencies.auditWriter),
          user && dependencies.auditWriter?.append({ actor: user,
            action: "access.denied", ...target,
            outcome: "denied", correlationId: response.locals.correlationId }),
        ]).then(() => {
          response.status(403).json({ code: "permission-denied", error: "You do not have permission to access this feature." });
        }).catch(() => {
          response.status(503).json({ code: "unavailable", error: "Authorization is temporarily unavailable. Try again." });
        });
        return;
      }
      if (error instanceof AuditUnavailableError) {
        response.status(503).json({ code: "unavailable", error: "Audit services are temporarily unavailable." });
        return;
      }
      if (error instanceof StaffAccountError) {
        response.status(error.status).json({ error: error.message }); return;
      }
      if (error instanceof AccountInputError) {
        response.status(400).json({ code: "invalid-argument", error: error.message });
        return;
      }
      if (error instanceof BackendUnavailableError) {
        response.status(503).json({ code: "unavailable", error: "Account services are unavailable. Try again." });
        return;
      }
      if (error instanceof AuthenticationError) {
        response.status(error.statusCode).json({ code: error.code, error: error.message });
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
      if (error instanceof ClientIntakeError) {
        response.status(error.statusCode).json({ error: error.message });
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

      console.error("Unhandled FitNEP API error", error);
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

function toApiIntakeWorkspace(workspace: IntakeWorkspace) {
  return {
    client_id: workspace.clientId,
    answers: workspace.answers,
    version: workspace.version,
    draft_revision: workspace.draftRevision,
    membership_active: workspace.membershipActive,
    profile_ready: workspace.profileReady,
    guardian_consent_confirmed: workspace.guardianConfirmed,
    latest: workspace.latest && toApiClientIntake(workspace.latest),
  };
}

function toApiClientIntake(intake: ClientIntakeRecord) {
  return {
    version: intake.version ?? 1,
    ...(intake.reviewRevision === undefined ? {} : { review_revision: intake.reviewRevision }),
    client_id: intake.clientId,
    allergies: intake.allergies,
    medical_conditions: intake.medicalConditions,
    sections: intake.sections.map(section => ({
      title: section.title,
      fields: section.fields.map(field => ({
        label: field.label,
        value: field.value,
      })),
    })),
    submitted_at: intake.submittedAt,
    updated_at: intake.updatedAt,
    status: intake.status,
    review_action: intake.review.action,
    review_note: intake.review.note,
    review_updated_at: intake.review.updatedAt,
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

function toApiStaffAccount(account: StaffAccount) {
  return {
    uid: account.uid,
    name: account.name,
    email: account.email,
    role: account.role,
    is_active: account.isActive,
  };
}
