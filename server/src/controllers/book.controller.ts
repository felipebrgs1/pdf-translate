import { Hono } from 'hono'
import type { Env } from '../models/types'
import { getUser } from '../middleware/auth'
import { checkQuota, listBooksForUser, userPrefix } from '../services/book.service'

export const bookRoutes = new Hono<Env>()

function extractKey(c: { req: { path: string; param: (n: string) => string | undefined } }, prefix: string): string {
  // Tenta param first (para compat com :key e com %2F), depois slice do path (suporta / com ou sem encode)
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

bookRoutes.get('/api/books', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  const books = await listBooksForUser(c.env, user)
  return c.json(books)
})

bookRoutes.post('/api/books', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  let name = 'Sem título'
  try { name = decodeURIComponent(c.req.header('x-file-name') ?? '') || name } catch {}
  const body = await c.req.arrayBuffer()
  if (!body.byteLength) return c.json({ error: 'empty file' }, 400)
  const quota = await checkQuota(c.env, user, body.byteLength)
  if (!quota.ok) return c.json({ error: `limite de 150MB atingido (usado ${(quota.used / 1024 / 1024).toFixed(1)}MB)` }, 413)
  const key = `${userPrefix(user)}${crypto.randomUUID()}.pdf`
  await c.env.BOOKS.put(key, body, { httpMetadata: { contentType: 'application/pdf' }, customMetadata: { name } })
  return c.json({ key, name })
})

bookRoutes.get('/api/books/*', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  const key = extractKey(c as any, '/api/books/')
  if (!key) return c.json({ error: 'not found' }, 404)
  // verifica ownership por prefixo (ou legado sem prefixo para felipe)
  if (!key.startsWith(userPrefix(user)) && key !== userPrefix(user).slice(0, -1) && !(user.toLowerCase() === 'felipe@gmail.com' && !key.includes('/'))) {
    const obj = await c.env.BOOKS.get(key)
    if (!obj) return c.json({ error: 'not found' }, 404)
    if (!key.startsWith(userPrefix(user)) && user.toLowerCase() !== 'felipe@gmail.com') return c.json({ error: 'not found' }, 404)
    return new Response(obj.body, { headers: { 'Content-Type': 'application/pdf', 'Cache-Control': 'private, max-age=3600' } })
  }
  const obj = await c.env.BOOKS.get(key)
  if (!obj) return c.json({ error: 'not found' }, 404)
  return new Response(obj.body, { headers: { 'Content-Type': 'application/pdf', 'Cache-Control': 'private, max-age=3600' } })
})

bookRoutes.put('/api/books/*', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  const key = extractKey(c as any, '/api/books/')
  if (!key) return c.json({ error: 'not found' }, 404)
  if (!key.startsWith(userPrefix(user)) && !(user.toLowerCase() === 'felipe@gmail.com' && !key.includes('/'))) {
    return c.json({ error: 'not found' }, 404)
  }
  const existing = await c.env.BOOKS.get(key)
  if (!existing) return c.json({ error: 'not found' }, 404)
  const body = await c.req.arrayBuffer()
  if (!body.byteLength) return c.json({ error: 'empty file' }, 400)
  const quota = await checkQuota(c.env, user, body.byteLength - existing.size)
  if (!quota.ok) return c.json({ error: 'limite de 150MB atingido' }, 413)
  await c.env.BOOKS.put(key, body, { httpMetadata: { contentType: 'application/pdf' }, customMetadata: existing.customMetadata ?? {} })
  return c.json({ ok: true, key })
})

bookRoutes.delete('/api/books/*', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  const key = extractKey(c as any, '/api/books/')
  if (!key) return c.json({ error: 'not found' }, 404)
  if (!key.startsWith(userPrefix(user)) && !(user.toLowerCase() === 'felipe@gmail.com' && !key.includes('/'))) {
    return c.json({ error: 'not found' }, 404)
  }
  await Promise.all([c.env.BOOKS.delete(key), c.env.BOOKS.delete(`thumbs/${key}.webp`), c.env.PROGRESS.delete(`progress:${user.toLowerCase()}:${key}`), c.env.PROGRESS.delete(`progress:${key}`)])
  return c.json({ ok: true })
})
