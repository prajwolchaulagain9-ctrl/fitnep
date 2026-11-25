import { AuthenticatedUser } from "./domain";
import type { Transaction } from "firebase-admin/firestore";
import type { HealthReadTarget } from "./audited_health_reads";

export const recordSharingChoices = {
  "nutrition-records": "shareNutritionRecords",
  "meal-photos": "shareMealPhotos",
  "progress-photos": "shareProgressPhotos",
  "activity-data": "shareActivityData",
} as const;

export type RecordCategory = keyof typeof recordSharingChoices;
export type RecordDetails = Record<string, string | number>;
export type PrivateRecord = { id: string; recorded_at: string; details: RecordDetails };
export type PrivatePhoto = { bytes: Buffer; contentType: string };

export class PrivateRecordsError extends Error {
  constructor(readonly status: 400 | 404 | 503, message: string) {
    super(message);
  }
}

export interface PrivateRecordsStore {
  readResource<T>(actor: AuthenticatedUser, target: HealthReadTarget,
    load: (transaction: Transaction) => Promise<{ data: T; recordIds?: readonly string[] }>, correlationId?: string): Promise<T>;
  list(actor: AuthenticatedUser, clientId: string, category: RecordCategory, after?: string, correlationId?: string): Promise<PrivateRecord[]>;
  read(actor: AuthenticatedUser, clientId: string, category: RecordCategory, id: string, correlationId?: string): Promise<PrivateRecord>;
  collect(actor: AuthenticatedUser, clientId: string, category: RecordCategory, body: unknown): Promise<PrivateRecord>;
  readPhoto(actor: AuthenticatedUser, clientId: string, category: RecordCategory, id: string, correlationId?: string): Promise<PrivatePhoto>;
}

export function parseRecordCategory(value: string | undefined): RecordCategory {
  if (!value || !Object.hasOwn(recordSharingChoices, value)) {
    throw new PrivateRecordsError(404, "Record category not found.");
  }
  return value as RecordCategory;
}

export function parseRecordId(value: string | undefined): string {
  if (!value || !/^[A-Za-z0-9_-]{1,128}$/.test(value)) {
    throw new PrivateRecordsError(400, "Invalid record identifier.");
  }
  return value;
}

const maxPhotoBytes = 512 * 1024;
export const photoContentTypes = ["image/jpeg", "image/png", "image/webp"];
export const photoUploadOptions = { limit: maxPhotoBytes, type: photoContentTypes };

export function isPhotoCategory(category: RecordCategory): boolean {
  return category === "meal-photos" || category === "progress-photos";
}

export function photoContentType(bytes: Buffer): string | null {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return "image/jpeg";
  }
  if (bytes.length >= 8 && bytes.subarray(0, 8).equals(Buffer.from("89504e470d0a1a0a", "hex"))) {
    return "image/png";
  }
  if (bytes.length >= 12 && bytes.toString("ascii", 0, 4) === "RIFF" &&
      bytes.toString("ascii", 8, 12) === "WEBP") {
    return "image/webp";
  }
  return null;
}

export function parseRecord(category: RecordCategory, body: unknown): { details: RecordDetails; photo?: Buffer } {
  if (isPhotoCategory(category)) {
    const contentType = Buffer.isBuffer(body) && body.length <= maxPhotoBytes
      ? photoContentType(body) : null;
    if (!Buffer.isBuffer(body) || !contentType) {
      throw new PrivateRecordsError(400, "Supply a JPEG, PNG or WebP photo up to 512 KiB.");
    }
    return { details: { content_type: contentType }, photo: body };
  }
  if (typeof body !== "object" || body === null || Array.isArray(body) || Buffer.isBuffer(body)) {
    throw new PrivateRecordsError(400, "Invalid record.");
  }
  const fields = body as Record<string, unknown>;
  if (category === "activity-data") {
    const { steps, active_minutes } = fields;
    if (typeof steps === "number" && Number.isInteger(steps) && steps >= 0 &&
        typeof active_minutes === "number" && Number.isInteger(active_minutes) && active_minutes >= 0) {
      return { details: { steps, active_minutes } };
    }
    throw new PrivateRecordsError(400, "Supply nonnegative step and activity minute counts.");
  }
  const foodName = typeof fields.food_name === "string" ? fields.food_name.trim() : "";
  const calories = fields.calories;
  if (foodName.length === 0 || foodName.length > 200 ||
      typeof calories !== "number" || !Number.isFinite(calories) || calories < 0) {
    throw new PrivateRecordsError(400, "Supply a food name and a nonnegative calorie value.");
  }
  return { details: { food_name: foodName, calories } };
}
