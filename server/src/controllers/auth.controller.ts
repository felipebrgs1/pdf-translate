import { Hono } from 'hono'
import { deleteCookie, setCookie } from 'hono/cookie'
import type { Env } from '../models/types'
import { SESSION_COOKIE, SESSION_TTL } from '../models/types'
import { getUser } from '../middleware/auth'
import { createUser, getUserHash, sha256Hex, signSession, verifyUser } from '../services/auth.service'

export const authRoutes = new Hono<Env>()

authRoutes.post('/api/register', async (c) => {
  const { email, password } = await c.req.json<{ email?: string; password?: string }>()
  const e = email?.trim().toLowerCase()
  if (!e || !password || password.length < 6) return c.json({ error: 'email e senha (min 6) obrigatórios' }, 400)
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e)) return c.json({ error: 'email inválido' }, 400)
  const existing = await getUserHash(c.env, e)
  if (existing) return c.json({ error: 'usuário já existe' }, 409)
  const hash = await sha256Hex(password)
  await createUser(c.env, e, hash)
  const token = await signSession(e, c.env.JWT_SECRET)
  setCookie(c, SESSION_COOKIE, token, { httpOnly: true, secure: true, sameSite: 'Lax', path: '/', maxAge: SESSION_TTL })
  return c.json({ ok: true, token })
})

authRoutes.post('/api/login', async (c) => {
  const { email, password } = await c.req.json<{ email?: string; password?: string }>()
  if (!email || !password) return c.json({ error: 'Credenciais inválidas' }, 401)
  const e = email.toLowerCase()
  const ok = await verifyUser(c.env, e, password)
  if (!ok) return c.json({ error: 'Credenciais inválidas' }, 401)
  const token = await signSession(e, c.env.JWT_SECRET)
  setCookie(c, SESSION_COOKIE, token, { httpOnly: true, secure: true, sameSite: 'Lax', path: '/', maxAge: SESSION_TTL })
  return c.json({ ok: true, token })
})

authRoutes.post('/api/logout', (c) => {
  deleteCookie(c, SESSION_COOKIE, { path: '/' })
  return c.json({ ok: true })
})

authRoutes.get('/api/me', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  return c.json({ email: user })
})
