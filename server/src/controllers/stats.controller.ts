import { Hono } from 'hono'
import type { Env } from '../models/types'
import { getUser } from '../middleware/auth'
import { clampCount, readDailyStats, writeDailyStats } from '../services/stats.service'

export const statsRoutes = new Hono<Env>()

statsRoutes.get('/api/stats', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  return c.json({ days: await readDailyStats(c.env, user) })
})

statsRoutes.post('/api/stats', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  const body = await c.req.json<{ date?: string; pages?: number; minutes?: number; highlights?: number }>()
  const date = /^\d{4}-\d{2}-\d{2}$/.test(body.date ?? '') ? body.date! : new Date().toISOString().slice(0, 10)
  const days = await readDailyStats(c.env, user)
  const day = days[date] ?? { pages: 0, minutes: 0, highlights: 0 }
  day.pages = Math.min(day.pages + clampCount(body.pages, 2000), 100000)
  day.minutes = Math.min(day.minutes + clampCount(body.minutes, 1440), 100000)
  day.highlights = Math.min(day.highlights + clampCount(body.highlights, 5000), 100000)
  days[date] = day
  await writeDailyStats(c.env, user, days)
  return c.json(day)
})
