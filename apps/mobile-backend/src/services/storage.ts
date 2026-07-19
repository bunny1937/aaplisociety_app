import { S3Client, PutObjectCommand, GetObjectCommand } from "@aws-sdk/client-s3"
import { getSignedUrl } from "@aws-sdk/s3-request-presigner"
import { randomUUID } from "node:crypto"
import { env } from "../config/env.js"

const s3 = new S3Client({
  region: "auto",
  endpoint: env.r2.endpoint,
  credentials: {
    accessKeyId: env.r2.accessKeyId ?? "",
    secretAccessKey: env.r2.secretAccessKey ?? "",
  },
})

// Keys are always tenant-scoped: societyId/<folder>/<uuid>
export function buildKey(societyId: string, folder: string, ext: string): string {
  return `${societyId}/${folder}/${randomUUID()}.${ext.replace(/^\./, "")}`
}

export async function presignUpload(key: string, contentType: string): Promise<string> {
  return getSignedUrl(s3, new PutObjectCommand({
    Bucket: env.r2.bucket, Key: key, ContentType: contentType,
  }), { expiresIn: 300 })
}

export async function presignDownload(key: string): Promise<string> {
  return getSignedUrl(s3, new GetObjectCommand({
    Bucket: env.r2.bucket, Key: key,
  }), { expiresIn: 600 })
}

// Server-side upload for small, backend-proxied files (tenant-request
// documents) where strict size/type validation matters more than saving
// backend bandwidth — see design spec section on upload approach.
export async function uploadBuffer(key: string, body: Buffer, contentType: string): Promise<void> {
  await s3.send(new PutObjectCommand({
    Bucket: env.r2.bucket, Key: key, Body: body, ContentType: contentType,
  }))
}
