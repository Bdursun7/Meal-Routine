export class AppError extends Error {
  readonly code: string
  readonly status: number
  readonly existingProviders?: string[]

  constructor(code: string, status: number, existingProviders?: string[]) {
    super(code)
    this.code = code
    this.status = status
    this.existingProviders = existingProviders
  }
}
