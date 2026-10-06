export interface RateLimiter {
  allow(key: string, now?: number): boolean
}

export function createRateLimiter(options: { windowMs: number; max: number }): RateLimiter {
  const hits = new Map<string, number[]>()
  return {
    allow(key, now = Date.now()) {
      const start = now - options.windowMs
      const recent = (hits.get(key) ?? []).filter((time) => time > start)
      if (recent.length >= options.max) {
        hits.set(key, recent)
        return false
      }
      recent.push(now)
      hits.set(key, recent)
      return true
    },
  }
}
