import { applicationDefault, cert, deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";

import { createFitnepDependencies } from "./api_factory";
import { mountHostedAuth } from "./hosted_auth";
import { HostedConfigurationError, readHostedConfig } from "./hosted_config";
import { createNotificationApp } from "./http_app";
import { FirestorePlatformSessionService } from "./platform_sessions";
import { startWorkflowRecovery } from "./workflow_delivery";
import { CloudinaryPhotoConfigError } from "./cloudinary_photo_storage";

function start() {
  const config = readHostedConfig(process.env);
  const firebase = initializeApp({
    projectId: config.projectId,
    credential: config.serviceAccount ? cert(config.serviceAccount) : applicationDefault(),
  });
  const auth = getAuth(firebase);
  const firestore = getFirestore(firebase);
  const dependencies = createFitnepDependencies(auth, firestore);
  const recovery = startWorkflowRecovery(firestore, auth, () => dependencies.privateRecordsStore.recoverPhotoUploads());
  const authAdapter = mountHostedAuth(auth, firestore, dependencies.authVerifier, process.env);
  const api = createNotificationApp({
    ...dependencies,
    recoverCommittedEvents: recovery.drain,
    platformSessions: new FirestorePlatformSessionService(firestore, dependencies.auditWriter, config.idleTimeoutSeconds),
    manualVerificationEnabled: false,
    health: {
      buildSha: config.buildSha,
      checkReady: async () => { await firestore.doc("_runtime/health").get(); },
    },
  });
  const app = authAdapter;
  app.use(api);
  // Render terminates HTTPS and forwards to the assigned PORT.
  const server = app.listen(config.port, "0.0.0.0", () => {
    console.log("FitNEP API listening on port " + config.port + "; build " + config.buildSha);
  });
  server.on("error", () => {
    console.error("The FitNEP API could not bind its configured port.");
    void deleteApp(firebase).finally(() => { process.exitCode = 1; });
  });
  const close = () => {
    recovery.stop();
    const deadline = setTimeout(() => process.exit(1), 10_000);
    deadline.unref();
    server.close(() => { void deleteApp(firebase).finally(() => process.exit(0)); });
  };
  process.once("SIGINT", close);
  process.once("SIGTERM", close);
}

try { start(); } catch (error) {
  console.error(error instanceof HostedConfigurationError || error instanceof CloudinaryPhotoConfigError
    ? error.message
    : "The FitNEP API could not initialize. Check the host's Firebase credentials.");
  process.exitCode = 1;
}
