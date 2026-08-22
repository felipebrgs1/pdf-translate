import { Hono } from 'hono'
import type { Env } from '../models/types'
import { getUser } from '../middleware/auth'

export const thumbRoutes = new Hono<Env>()

thumbRoutes.post('/api/thumbs', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  const bookKey = c.req.header('x-book-key')
  if (!bookKey) return c.json({ error: 'missing x-book-key' }, 400)
  // valida ownership
  const prefix = `${user.toLowerCase()}/`
  if (!bookKey.startsWith(prefix) && !(user.toLowerCase() === 'felipe@gmail.com' && !bookKey.includes('/'))) {
    return c.json({ error: 'not found' }, 404)
  }
  const body = await c.req.arrayBuffer()
  if (!body.byteLength) return c.json({ error: 'empty file' }, 400)
  await c.env.BOOKS.put(`thumbs/${bookKey}.webp`, body, { httpMetadata: { contentType: 'image/webp' } })
  return c.json({ ok: true })
})

thumbRoutes.get('/api/thumbs/:key', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  const key = c.req.param('key')
  const prefix = `${user.toLowerCase()}/`
  if (!key.startsWith(prefix) && !(user.toLowerCase() === 'felipe@gmail.com' && !key.includes('/'))) {
    return c.json({ error: 'not found' }, 404)
  }
  const obj = await c.env.BOOKS.get(`thumbs/${key}.webp`)
  if (!obj) return c.json({ error: 'not found' }, 404)
  return new Response(obj.body, { headers: { 'Content-Type': 'image/webp', 'Cache-Control': 'private, max-age=86400' } })
})
