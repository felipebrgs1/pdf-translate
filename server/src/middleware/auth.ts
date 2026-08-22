import { getCookie } from 'hono/cookie'
import { verify } from 'hono/jwt'
import type { Env } from '../models/types'
import { SESSION_COOKIE } from '../models/types'

export async function getUser(c: { req: { raw: Request }; env: Env['Bindings'] }): Promise<string | null> {
  let token: string | undefined = getCookie(c as never, SESSION_COOKIE) as string | undefined
  if (!token) {
    const auth = c.req.header('authorization') ?? c.req.header('Authorization')
    if (auth?.toLowerCase().startsWith('bearer ')) token = auth.slice(7).trim()
  }
  if (!token) return null
  try {
    const payload = await verify(token, c.env.JWT_SECRET, 'HS256')
    return payload.sub as string
  } catch {
    return null
  }
}

export function authMiddleware(protectedPaths: string[]) {
  return async (c: any, next: any) => {
    const path: string = c.req.path
    const needsAuth = protectedPaths.some((p) => {
      if (p.endsWith('/*')) return path.startsWith(p.slice(0, -2))
      if (p.endsWith('*')) return path.startsWith(p.slice(0, -1))
      return path === p || path.startsWith(p + '/')
    })
    if (!needsAuth) return next()
    const user = await getUser(c)
    if (!user) return c.json({ error: 'unauthorized' }, 401)
    c.set('user', user)
    await next()
  }
}
