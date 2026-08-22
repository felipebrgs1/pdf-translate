export type Env = {
  Bindings: {
    BOOKS: R2Bucket
    PROGRESS: KVNamespace
    JWT_SECRET: string
    // legado single-user (mantido para fallback)
    ALLOWED_EMAIL?: string
    PASSWORD_HASH?: string
  }
}

export interface DayStats {
  pages: number
  minutes: number
  highlights: number
}

export interface BookProgress {
  page: number
  totalPages: number
  percent: number
  updatedAt: string
}

export const SESSION_COOKIE = 'session'
export const SESSION_TTL = 60 * 60 * 24 * 30
export const STORAGE_QUOTA = 150 * 1024 * 1024 // 150MB por user

export const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms))
