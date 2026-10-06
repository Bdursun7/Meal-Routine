export interface AppConfig {
  nodeEnv: string
  databaseUrl: string
  jwtSecret: string
  googleClientId: string
  appleBundleId: string
  accessTtlSeconds: number
  refreshTtlSeconds: number
  port: number
  rateLimitMax: number
  rateLimitWindowMs: number
  apiVersion: string
  /** Exact browser origin allowed to call the API. Empty disables CORS. */
  corsOrigin: string
}

function numberOr(raw: string | undefined, fallback: number): number {
  if (raw === undefined || raw.trim() === '') return fallback
  const value = Number(raw)
  return Number.isFinite(value) ? value : fallback
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  return {
    nodeEnv: env.NODE_ENV?.trim() || 'development',
    databaseUrl: env.DATABASE_URL?.trim() ?? '',
    jwtSecret: env.JWT_SECRET?.trim() ?? '',
    googleClientId: env.GOOGLE_CLIENT_ID_IOS?.trim() ?? '',
    appleBundleId: env.APPLE_BUNDLE_ID?.trim() || 'com.mealroutine.app',
    accessTtlSeconds: numberOr(env.ACCESS_TTL_SECONDS, 900),
    refreshTtlSeconds: numberOr(env.REFRESH_TTL_SECONDS, 60 * 60 * 24 * 30),
    port: numberOr(env.PORT, 8080),
    rateLimitMax: numberOr(env.RATE_LIMIT_AUTH_MAX, 30),
    rateLimitWindowMs: numberOr(env.RATE_LIMIT_WINDOW_MS, 60_000),
    apiVersion: 'v1',
    corsOrigin: env.CORS_ORIGIN?.trim() ?? '',
  }
}

export function assertRuntimeConfig(config: AppConfig): void {
  if (!config.databaseUrl) {
    throw new Error('DATABASE_URL is required. See server/db/README.md.')
  }
  if (config.jwtSecret.length < 32) {
    throw new Error('JWT_SECRET must be at least 32 characters.')
  }
  if (config.corsOrigin === '*') {
    throw new Error('CORS_ORIGIN must be an exact origin. A wildcard is not allowed.')
  }
}
