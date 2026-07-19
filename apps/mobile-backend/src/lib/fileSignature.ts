// Detects a file's real type from its content (magic bytes), independent of
// the client-declared multipart Content-Type header — which is fully
// attacker-controlled and must never be trusted for an accept/reject
// decision. Closes the "rename a payload to aadhaar.jpg" class of bypass.
// Only covers the narrow set of types this app accepts; extend deliberately.
export type DetectedFileType = "application/pdf" | "image/jpeg" | "image/png"

export function detectFileType(buffer: Buffer): DetectedFileType | null {
  if (buffer.length >= 5 && buffer.subarray(0, 5).toString("latin1") === "%PDF-") {
    return "application/pdf"
  }
  if (buffer.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
    return "image/jpeg"
  }
  if (
    buffer.length >= 8 &&
    buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4e && buffer[3] === 0x47 &&
    buffer[4] === 0x0d && buffer[5] === 0x0a && buffer[6] === 0x1a && buffer[7] === 0x0a
  ) {
    return "image/png"
  }
  return null
}
