import { STORAGE_QUOTA } from '../models/types'

export function userPrefix(user: string): string {
  return `${user.toLowerCase()}/`
}

export function isThumbKey(key: string): boolean {
  return key.startsWith('thumbs/')
}

export async function getUserUsage(env: { BOOKS: R2Bucket }, user: string): Promise<number> {
  let total = 0
  let cursor: string | undefined
  const prefix = userPrefix(user)
  do {
    const list = await env.BOOKS.list({ prefix, cursor })
    for (const obj of list.objects) {
      if (isThumbKey(obj.key)) continue
      total += obj.size
    }
    cursor = list.truncated ? list.cursor : undefined
  } while (cursor)
  return total
}

export async function checkQuota(env: { BOOKS: R2Bucket }, user: string, newFileBytes: number): Promise<{ ok: boolean; used: number }> {
  const used = await getUserUsage(env, user)
  return { ok: used + newFileBytes <= STORAGE_QUOTA, used }
}

export async function listBooksForUser(env: { BOOKS: R2Bucket; PROGRESS: KVNamespace }, user: string) {
  const prefix = userPrefix(user)
  const list = await env.BOOKS.list({ prefix, include: ['customMetadata'] })
  // compat: se user é o legado e ainda tem livros sem prefixo, também lista sem prefixo (migração suave)
  let legacy: R2Objects | null = null
  if (user.toLowerCase() === 'felipe@gmail.com') {
    const all = await env.BOOKS.list({ include: ['customMetadata'] })
    legacy = { objects: all.objects.filter((o) => !o.key.includes('/') && !isThumbKey(o.key)), truncated: false } as any
  }
  const books = [...list.objects, ...(legacy?.objects ?? [])].filter((o) => !isThumbKey(o.key))

  const progressByKey = new Map<string, unknown>()
  await Promise.all(
    books.map(async (obj) => {
      const raw = await env.PROGRESS.get(`progress:${user.toLowerCase()}:${obj.key}`) ?? await env.PROGRESS.get(`progress:${obj.key}`)
      if (!raw) return
      try { progressByKey.set(obj.key, JSON.parse(raw)) } catch {}
    })
  )

  return books.map((obj) => ({
    key: obj.key,
    name: obj.customMetadata?.name ?? obj.key,
    size: obj.size,
    uploaded: obj.uploaded,
    progress: progressByKey.get(obj.key) ?? null,
  }))
}
