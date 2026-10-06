export class AppError extends Error {
  readonly code: string
  readonly status: number
  readonly existingProviders?: string[]
  readonly details?: Record<string, unknown>

  constructor(
    code: string,
    status: number,
    existingProviders?: string[],
    details?: Record<string, unknown>,
  ) {
    super(code)
    this.code = code
    this.status = status
    this.existingProviders = existingProviders
    this.details = details
  }
}
