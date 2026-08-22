import { Hono } from 'hono'
import type { Env } from '../models/types'
import { getUser } from '../middleware/auth'

export const progressRoutes = new Hono<Env>()

function progressKey(user: string, bookKey: string) {
  return `progress:${user.toLowerCase()}:${bookKey}`
}

progressRoutes.get('/api/progress/:key', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  const key = c.req.param('key')
  const raw = await c.env.PROGRESS.get(progressKey(user, key)) ?? await c.env.PROGRESS.get(`progress:${key}`)
  if (!raw) return c.json({ error: 'not found' }, 404)
  try { return c.json(JSON.parse(raw)) } catch { return c.json({ error: 'corrupted' }, 500) }
})

progressRoutes.put('/api/progress/:key', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  const key = c.req.param('key')
  const { page, totalPages } = await c.req.json<{ page?: number; totalPages?: number }>()
  if (!Number.isInteger(page) || !Number.isInteger(totalPages) || page! < 1 || totalPages! < 1) {
    return c.json({ error: 'invalid progress' }, 400)
  }
  const p = Math.min(page!, totalPages!)
  const progress = { page: p, totalPages: totalPages!, percent: Math.round((p / totalPages!) * 1000) / 10, updatedAt: new Date().toISOString() }
  await c.env.PROGRESS.put(progressKey(user, key), JSON.stringify(progress))
  return c.json(progress)
})
