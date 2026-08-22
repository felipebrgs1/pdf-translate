import { Hono } from 'hono'
import type { Env } from '../models/types'
import { getUser } from '../middleware/auth'

function extractKey(c: { req: { path: string; param: (n: string) => string | undefined } }, prefix: string): string {
  try {
    const p = c.req.param('key') ?? c.req.param('*')
    if (p) {
      try { return decodeURIComponent(p) } catch { return p }
    }
  } catch {}
  const path = c.req.path as string
  const raw = path.startsWith(prefix) ? path.slice(prefix.length) : path.split('/').pop() ?? ''
  try { return decodeURIComponent(raw) } catch { return raw }
}

function progressKey(user: string, bookKey: string) {
  return `progress:${user.toLowerCase()}:${bookKey}`
}

export const progressRoutes = new Hono<Env>()

progressRoutes.get('/api/progress/*', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  const key = extractKey(c as any, '/api/progress/')
  if (!key) return c.json({ error: 'not found' }, 404)
  const raw = await c.env.PROGRESS.get(progressKey(user, key)) ?? await c.env.PROGRESS.get(`progress:${key}`)
  if (!raw) return c.json({ error: 'not found' }, 404)
  try { return c.json(JSON.parse(raw)) } catch { return c.json({ error: 'corrupted' }, 500) }
})

progressRoutes.put('/api/progress/*', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  const key = extractKey(c as any, '/api/progress/')
  if (!key) return c.json({ error: 'not found' }, 404)
  const { page, totalPages } = await c.req.json<{ page?: number; totalPages?: number }>()
  if (!Number.isInteger(page) || !Number.isInteger(totalPages) || page! < 1 || totalPages! < 1) {
    return c.json({ error: 'invalid progress' }, 400)
  }
  const p = Math.min(page!, totalPages!)
  const progress = { page: p, totalPages: totalPages!, percent: Math.round((p / totalPages!) * 1000) / 10, updatedAt: new Date().toISOString() }
  await c.env.PROGRESS.put(progressKey(user, key), JSON.stringify(progress))
  return c.json(progress)
})
