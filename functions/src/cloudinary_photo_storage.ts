import { v2 as cloudinary } from "cloudinary";

import { maxPhotoBytes, photoContentType, PrivateRecordsError } from "./private_records";

const imageFormats = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
} as const;

export type PhotoMimeType = keyof typeof imageFormats;

export function isPhotoMimeType(value: unknown): value is PhotoMimeType {
  return typeof value === "string" && Object.hasOwn(imageFormats, value);
}

export interface PrivatePhotoStorage {
  write(id: string, bytes: Buffer, contentType: PhotoMimeType): Promise<void>;
  read(id: string, contentType: PhotoMimeType): Promise<Buffer>;
}

export class CloudinaryPhotoConfigError extends Error {}

export function cloudinaryPhotoStorageFromEnv(url = process.env.CLOUDINARY_URL): PrivatePhotoStorage | undefined {
  if (!url?.trim()) return undefined;
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== "cloudinary:" || !/^[a-zA-Z0-9_-]+$/.test(parsed.hostname) ||
        !parsed.username || !parsed.password || parsed.port || parsed.search || parsed.hash ||
        (parsed.pathname !== "" && parsed.pathname !== "/")) {
      throw new Error("Invalid Cloudinary URL.");
    }
    return new CloudinaryPhotoStorage({
      cloud_name: parsed.hostname,
      api_key: decodeURIComponent(parsed.username),
      api_secret: decodeURIComponent(parsed.password),
    });
  } catch {
    throw new CloudinaryPhotoConfigError("CLOUDINARY_URL is invalid. Check the backend environment variable.");
  }
}

class CloudinaryPhotoStorage implements PrivatePhotoStorage {
  constructor(private readonly credentials: { cloud_name: string; api_key: string; api_secret: string }) {}

  write(id: string, bytes: Buffer, contentType: PhotoMimeType): Promise<void> {
    const publicId = photoPublicId(id);
    return new Promise((resolve, reject) => {
      const upload = cloudinary.uploader.upload_stream({
        ...this.credentials,
        resource_type: "image",
        type: "authenticated",
        asset_folder: "fitnep",
        use_asset_folder_as_public_id_prefix: false,
        public_id: publicId,
        overwrite: false,
        allowed_formats: [imageFormats[contentType]],
        timeout: 12_000,
        disable_promises: true,
      }, (error, result) => {
        if (error || result?.public_id !== publicId || result.type !== "authenticated" ||
            result.format !== imageFormats[contentType]) {
          reject(unavailable());
        } else {
          resolve();
        }
      });
      upload.on("error", () => reject(unavailable()));
      upload.end(bytes);
    });
  }

  async read(id: string, contentType: PhotoMimeType): Promise<Buffer> {
    const options = {
      ...this.credentials,
      resource_type: "image" as const,
      type: "authenticated" as const,
      expires_at: Math.floor(Date.now() / 1000) + 60,
    };
    const url = cloudinary.utils.private_download_url(photoPublicId(id), imageFormats[contentType], options);
    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(12_000), redirect: "error" });
      if (response.status === 404) throw new PrivateRecordsError(404, "Photo not found.");
      if (!response.ok || !response.body || Number(response.headers.get("content-length")) > maxPhotoBytes) {
        await response.body?.cancel();
        throw unavailable();
      }
      const chunks: Buffer[] = [];
      let size = 0;
      const reader = response.body.getReader();
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > maxPhotoBytes) {
          await reader.cancel();
          throw unavailable();
        }
        chunks.push(Buffer.from(value));
      }
      const bytes = Buffer.concat(chunks);
      if (photoContentType(bytes) !== contentType) throw unavailable();
      return bytes;
    } catch (error) {
      if (error instanceof PrivateRecordsError) throw error;
      throw unavailable();
    }
  }
}

function photoPublicId(id: string) {
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(id)) throw unavailable();
  return `fitnep-photo-${id}`;
}

function unavailable() {
  return new PrivateRecordsError(503, "Photo storage is temporarily unavailable.");
}
