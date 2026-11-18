import { rmSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const allowedTargets = new Set(["lib", ".test-build"]);
const targetName = process.argv[2];
if (!allowedTargets.has(targetName)) {
  throw new Error(`Refusing to remove unexpected build target: ${targetName}`);
}

const functionsRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const targetPath = resolve(functionsRoot, targetName);
if (dirname(targetPath) !== functionsRoot) {
  throw new Error(`Build target escaped the functions directory: ${targetPath}`);
}

rmSync(targetPath, { recursive: true, force: true });
