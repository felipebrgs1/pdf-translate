import { serve } from '@hono/node-server'
import { Hono } from 'hono'
import { cors } from 'hono/cors'

const app = new Hono()

app.use('*', cors())

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

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

const port = Number(process.env.PORT ?? 3000)
serve({ fetch: app.fetch, port }, (info) => {
  console.log(`server listening on http://localhost:${info.port}`)
})
