const sensitiveKeys = new Set([
  'identitytoken',
  'refreshtoken',
  'accesstoken',
  'authorization',
  'email',
  'givenname',
  'familyname',
  'displayname',
  'token',
  'devicetoken',
  'tokenhash',
  'name',
])

/** Drops sign-in payloads before anything is written to a log. */
export function redactSensitive(value: unknown): unknown {
  if (Array.isArray(value)) return value.map((item) => redactSensitive(item))
  if (!value || typeof value !== 'object') return value
  const output: Record<string, unknown> = {}
  for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
    output[key] = sensitiveKeys.has(key.toLowerCase()) ? '[redacted]' : redactSensitive(item)
  }
  return output
}
