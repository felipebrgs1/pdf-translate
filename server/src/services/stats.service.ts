import type { DayStats } from '../models/types'

function statsKey(user: string): string {
  return `stats:daily:${user.toLowerCase()}`
}

export async function readDailyStats(env: { PROGRESS: KVNamespace }, user: string): Promise<Record<string, DayStats>> {
  const raw = await env.PROGRESS.get(statsKey(user))
  // fallback global legado (antes do multi-user)
  const fallback = user.toLowerCase() === 'felipe@gmail.com' ? await env.PROGRESS.get('stats:daily') : null
  const src = raw ?? fallback
  if (!src) return {}
  try { return JSON.parse(src) ?? {} } catch { return {} }
}

export async function writeDailyStats(env: { PROGRESS: KVNamespace }, user: string, days: Record<string, DayStats>): Promise<void> {
  await env.PROGRESS.put(statsKey(user), JSON.stringify(days))
}

export const clampCount = (n: unknown, max: number) => Math.min(Math.max(Math.floor(Number(n) || 0), 0), max)
