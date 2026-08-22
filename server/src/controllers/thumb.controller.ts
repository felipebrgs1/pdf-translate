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

export const thumbRoutes = new Hono<Env>()

thumbRoutes.post('/api/thumbs', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  const bookKey = c.req.header('x-book-key')
  if (!bookKey) return c.json({ error: 'missing x-book-key' }, 400)
  const prefix = `${user.toLowerCase()}/`
  if (!bookKey.startsWith(prefix) && !(user.toLowerCase() === 'felipe@gmail.com' && !bookKey.includes('/'))) {
    return c.json({ error: 'not found' }, 404)
  }
  const body = await c.req.arrayBuffer()
  if (!body.byteLength) return c.json({ error: 'empty file' }, 400)
  await c.env.BOOKS.put(`thumbs/${bookKey}.webp`, body, { httpMetadata: { contentType: 'image/webp' } })
  return c.json({ ok: true })
})

thumbRoutes.get('/api/thumbs/*', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  const key = extractKey(c as any, '/api/thumbs/')
  if (!key) return c.json({ error: 'not found' }, 404)
  const prefix = `${user.toLowerCase()}/`
  if (!key.startsWith(prefix) && !(user.toLowerCase() === 'felipe@gmail.com' && !key.includes('/'))) {
    return c.json({ error: 'not found' }, 404)
  }
  const obj = await c.env.BOOKS.get(`thumbs/${key}.webp`)
  if (!obj) return c.json({ error: 'not found' }, 404)
  return new Response(obj.body, { headers: { 'Content-Type': 'image/webp', 'Cache-Control': 'private, max-age=86400' } })
})
