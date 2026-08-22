import { sign } from 'hono/jwt'
import { SESSION_TTL } from '../models/types'

const USER_PREFIX = 'user:'

export async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text))
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

export function userKey(email: string): string {
  return `${USER_PREFIX}${email.toLowerCase()}`
}

export async function getUserHash(env: { PROGRESS: KVNamespace }, email: string): Promise<string | null> {
  return env.PROGRESS.get(userKey(email))
}

export async function createUser(env: { PROGRESS: KVNamespace }, email: string, hash: string): Promise<void> {
  await env.PROGRESS.put(userKey(email), hash)
}

export async function verifyUser(env: { PROGRESS: KVNamespace; ALLOWED_EMAIL?: string; PASSWORD_HASH?: string }, email: string, password: string): Promise<boolean> {
  const hash = await sha256Hex(password)
  // tenta KV primeiro (multi-user)
  const stored = await env.PROGRESS.get(userKey(email))
  if (stored) return stored === hash
  // fallback legado single-user env
  if (env.ALLOWED_EMAIL && env.PASSWORD_HASH) {
    return email.toLowerCase() === env.ALLOWED_EMAIL.toLowerCase() && hash === env.PASSWORD_HASH
  }
  return false
}

export async function signSession(email: string, jwtSecret: string): Promise<string> {
  return sign({ sub: email.toLowerCase(), exp: Math.floor(Date.now() / 1000) + SESSION_TTL }, jwtSecret, 'HS256')
}
