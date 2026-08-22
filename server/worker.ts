import { Hono } from 'hono'
import { cors } from 'hono/cors'
import { deleteCookie, getCookie, setCookie } from 'hono/cookie'
import { sign, verify } from 'hono/jwt'

type Env = {
  Bindings: {
    BOOKS: R2Bucket
    PROGRESS: KVNamespace
    JWT_SECRET: string
    ALLOWED_EMAIL: string
    PASSWORD_HASH: string
  }
}

const SESSION_COOKIE = 'session'
const SESSION_TTL = 60 * 60 * 24 * 30

const app = new Hono<Env>()

// CORS para Flutter (web em localhost, mobile) — web legada servida do mesmo Worker não precisa mas não atrapalha
app.use('*', cors({
  origin: '*',
  allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowHeaders: ['Content-Type', 'Authorization', 'x-file-name', 'x-book-key'],
}))

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

async function sha256Hex(text: string) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text))
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

async function getUser(c: { req: { raw: Request }; env: Env['Bindings'] }) {
  let token = getCookie(c as never, SESSION_COOKIE) as string | undefined
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

app.post('/api/login', async (c) => {
  const { email, password } = await c.req.json<{ email?: string; password?: string }>()
  if (!email || !password) {
    return c.json({ error: 'Credenciais inválidas' }, 401)
  }
  const hash = await sha256Hex(password)
  if (email.toLowerCase() !== c.env.ALLOWED_EMAIL || hash !== c.env.PASSWORD_HASH) {
    return c.json({ error: 'Credenciais inválidas' }, 401)
  }
  const token = await sign(
    { sub: email.toLowerCase(), exp: Math.floor(Date.now() / 1000) + SESSION_TTL },
    c.env.JWT_SECRET,
    'HS256'
  )
  setCookie(c, SESSION_COOKIE, token, {
    httpOnly: true,
    secure: true,
    sameSite: 'Lax',
    path: '/',
    maxAge: SESSION_TTL
  })
  return c.json({ ok: true, token })
})

app.post('/api/logout', (c) => {
  deleteCookie(c, SESSION_COOKIE, { path: '/' })
  return c.json({ ok: true })
})

app.get('/api/me', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  return c.json({ email: user })
})

app.use('/api/books/*', async (c, next) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  await next()
})

app.get('/api/books', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  const [list] = await Promise.all([
    c.env.BOOKS.list({ include: ['customMetadata'] })
  ])

  const books = list.objects.filter((obj) => !obj.key.startsWith('thumbs/'))

  // leitura forte (single get) — list é eventualmente consistente e atrasaria a home
  const progressByKey = new Map<string, unknown>()
  await Promise.all(
    books.map(async (obj) => {
      const raw = await c.env.PROGRESS.get(`progress:${obj.key}`)
      if (!raw) return
      try {
        progressByKey.set(obj.key, JSON.parse(raw))
      } catch {
        // valor corrompido — ignora
      }
    })
  )

  return c.json(
    books.map((obj) => ({
      key: obj.key,
      name: obj.customMetadata?.name ?? obj.key,
      size: obj.size,
      uploaded: obj.uploaded,
      progress: progressByKey.get(obj.key) ?? null
    }))
  )
})

app.post('/api/books', async (c) => {
  let name = 'Sem título'
  try {
    name = decodeURIComponent(c.req.header('x-file-name') ?? '') || name
  } catch {
    // header sem encoding válido
  }
  const body = await c.req.arrayBuffer()
  if (!body.byteLength) return c.json({ error: 'empty file' }, 400)

  const key = `${crypto.randomUUID()}.pdf`
  await c.env.BOOKS.put(key, body, {
    httpMetadata: { contentType: 'application/pdf' },
    customMetadata: { name }
  })
  return c.json({ key, name })
})

app.get('/api/books/:key', async (c) => {
  const obj = await c.env.BOOKS.get(c.req.param('key'))
  if (!obj) return c.json({ error: 'not found' }, 404)
  return new Response(obj.body, {
    headers: { 'Content-Type': 'application/pdf', 'Cache-Control': 'private, max-age=3600' }
  })
})

app.get('/api/progress/:key', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  const raw = await c.env.PROGRESS.get(`progress:${c.req.param('key')}`)
  if (!raw) return c.json({ error: 'not found' }, 404)
  try {
    return c.json(JSON.parse(raw))
  } catch {
    return c.json({ error: 'corrupted' }, 500)
  }
})

app.put('/api/progress/:key', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  const key = c.req.param('key')
  const { page, totalPages } = await c.req.json<{ page?: number; totalPages?: number }>()
  if (!Number.isInteger(page) || !Number.isInteger(totalPages) || page < 1 || totalPages < 1) {
    return c.json({ error: 'invalid progress' }, 400)
  }
  const p = Math.min(page, totalPages)
  const progress = {
    page: p,
    totalPages,
    percent: Math.round((p / totalPages) * 1000) / 10,
    updatedAt: new Date().toISOString()
  }
  await c.env.PROGRESS.put(`progress:${key}`, JSON.stringify(progress))
  return c.json(progress)
})

app.use('/api/thumbs/*', async (c, next) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  await next()
})

app.use('/api/stats', async (c, next) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  await next()
})

interface DayStats {
  pages: number
  minutes: number
  highlights: number
}

async function readDailyStats(env: Env['Bindings']): Promise<Record<string, DayStats>> {
  const raw = await env.PROGRESS.get('stats:daily')
  if (!raw) return {}
  try {
    return JSON.parse(raw) ?? {}
  } catch {
    return {}
  }
}

const clampCount = (n: unknown, max: number) =>
  Math.min(Math.max(Math.floor(Number(n) || 0), 0), max)

app.get('/api/stats', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  return c.json({ days: await readDailyStats(c.env) })
})

// soma um delta no dia informado (data local do cliente, formato YYYY-MM-DD)
app.post('/api/stats', async (c) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  const body = await c.req.json<{
    date?: string
    pages?: number
    minutes?: number
    highlights?: number
  }>()

  const date = /^\d{4}-\d{2}-\d{2}$/.test(body.date ?? '')
    ? body.date!
    : new Date().toISOString().slice(0, 10)

  const days = await readDailyStats(c.env)
  const day = days[date] ?? { pages: 0, minutes: 0, highlights: 0 }
  day.pages = Math.min(day.pages + clampCount(body.pages, 2000), 100000)
  day.minutes = Math.min(day.minutes + clampCount(body.minutes, 1440), 100000)
  day.highlights = Math.min(day.highlights + clampCount(body.highlights, 5000), 100000)
  days[date] = day

  await c.env.PROGRESS.put('stats:daily', JSON.stringify(days))
  return c.json(day)
})

app.use('/api/thumbs', async (c, next) => {
  const user = await getUser(c)
  if (!user) return c.json({ error: 'unauthorized' }, 401)
  await next()
})

app.post('/api/thumbs', async (c) => {
  const bookKey = c.req.header('x-book-key')
  if (!bookKey) return c.json({ error: 'missing x-book-key' }, 400)
  const body = await c.req.arrayBuffer()
  if (!body.byteLength) return c.json({ error: 'empty file' }, 400)
  await c.env.BOOKS.put(`thumbs/${bookKey}.webp`, body, {
    httpMetadata: { contentType: 'image/webp' }
  })
  return c.json({ ok: true })
})

app.get('/api/thumbs/:key', async (c) => {
  const obj = await c.env.BOOKS.get(`thumbs/${c.req.param('key')}.webp`)
  if (!obj) return c.json({ error: 'not found' }, 404)
  return new Response(obj.body, {
    headers: { 'Content-Type': 'image/webp', 'Cache-Control': 'private, max-age=86400' }
  })
})

app.delete('/api/books/:key', async (c) => {
  const key = c.req.param('key')
  await Promise.all([c.env.BOOKS.delete(key), c.env.BOOKS.delete(`thumbs/${key}.webp`)])
  return c.json({ ok: true })
})

function parseGtx(data: unknown, fallbackSource: string) {
  const d = data as [[string][][], unknown, string]
  return {
    translated: (d?.[0] ?? []).map((part) => part[0]).join(''),
    source: d?.[2] ?? fallbackSource
  }
}

async function translateGtx(q: string, source: string, target: string) {
  const url =
    'https://translate.googleapis.com/translate_a/single' +
    `?client=gtx&sl=${encodeURIComponent(source)}&tl=${encodeURIComponent(target)}&dt=t&q=${encodeURIComponent(q)}`

  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const res = await fetch(url, {
        headers: { 'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64)' }
      })
      if (res.ok) return parseGtx(await res.json(), source)
    } catch {
      // tenta de novo
    }
    await sleep(300 * (attempt + 1))
  }
  return null
}

async function translateChromeEx(q: string, source: string, target: string) {
  const url =
    'https://clients5.google.com/translate_a/t' +
    `?client=dict-chrome-ex&sl=${encodeURIComponent(source)}&tl=${encodeURIComponent(target)}&q=${encodeURIComponent(q)}`

  try {
    const res = await fetch(url, {
      headers: { 'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64)' }
    })
    if (!res.ok) return null
    const data = (await res.json()) as [string, string][]
    return {
      translated: data.map((part) => part[0]).join(''),
      source: data[0]?.[1] ?? source
    }
  } catch {
    return null
  }
}

app.get('/api/translate', async (c) => {
  const q = c.req.query('q')
  const target = c.req.query('target') ?? 'pt'
  const source = c.req.query('source') ?? 'auto'

  if (!q?.trim()) {
    return c.json({ error: 'missing q' }, 400)
  }

  const result =
    (await translateGtx(q, source, target)) ?? (await translateChromeEx(q, source, target))

  if (!result) {
    return c.json({ error: 'translation failed' }, 502)
  }
  return c.json({ ...result, target })
})

export default app
