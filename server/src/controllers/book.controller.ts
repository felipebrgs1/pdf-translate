import { Hono } from 'hono'
import type { Env } from '../models/types'
import { getUser } from '../middleware/auth'
import { checkQuota, listBooksForUser, userPrefix } from '../services/book.service'

export const bookRoutes = new Hono<Env>()

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

bookRoutes.get('/api/books/:key', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  // key vem encodada com / — Hono já decodifica
  const key = c.req.param('key')
  // verifica ownership por prefixo (ou legado sem prefixo para felipe)
  if (!key.startsWith(userPrefix(user)) && key !== userPrefix(user).slice(0, -1) && !(user.toLowerCase() === 'felipe@gmail.com' && !key.includes('/'))) {
    // tenta buscar mesmo assim — se não for do user retorna 404 para não vazar existência
    const obj = await c.env.BOOKS.get(key)
    if (!obj) return c.json({ error: 'not found' }, 404)
    // legado: permite felipe acessar chaves sem prefixo
    if (!key.startsWith(userPrefix(user)) && user.toLowerCase() !== 'felipe@gmail.com') return c.json({ error: 'not found' }, 404)
    return new Response(obj.body, { headers: { 'Content-Type': 'application/pdf', 'Cache-Control': 'private, max-age=3600' } })
  }
  const obj = await c.env.BOOKS.get(key)
  if (!obj) return c.json({ error: 'not found' }, 404)
  return new Response(obj.body, { headers: { 'Content-Type': 'application/pdf', 'Cache-Control': 'private, max-age=3600' } })
})

bookRoutes.put('/api/books/:key', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  const key = c.req.param('key')
  if (!key.startsWith(userPrefix(user)) && !(user.toLowerCase() === 'felipe@gmail.com' && !key.includes('/'))) {
    return c.json({ error: 'not found' }, 404)
  }
  const existing = await c.env.BOOKS.get(key)
  if (!existing) return c.json({ error: 'not found' }, 404)
  const body = await c.req.arrayBuffer()
  if (!body.byteLength) return c.json({ error: 'empty file' }, 400)
  // quota: desconta tamanho antigo
  const quota = await checkQuota(c.env, user, body.byteLength - existing.size)
  if (!quota.ok) return c.json({ error: 'limite de 150MB atingido' }, 413)
  await c.env.BOOKS.put(key, body, { httpMetadata: { contentType: 'application/pdf' }, customMetadata: existing.customMetadata ?? {} })
  return c.json({ ok: true, key })
})

bookRoutes.delete('/api/books/:key', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  const key = c.req.param('key')
  if (!key.startsWith(userPrefix(user)) && !(user.toLowerCase() === 'felipe@gmail.com' && !key.includes('/'))) {
    return c.json({ error: 'not found' }, 404)
  }
  await Promise.all([c.env.BOOKS.delete(key), c.env.BOOKS.delete(`thumbs/${key}.webp`), c.env.PROGRESS.delete(`progress:${user.toLowerCase()}:${key}`), c.env.PROGRESS.delete(`progress:${key}`)])
  return c.json({ ok: true })
})
