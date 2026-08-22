import { Hono } from 'hono'
import { cors } from 'hono/cors'
import type { Env } from './models/types'
import { authRoutes } from './controllers/auth.controller'
import { bookRoutes } from './controllers/book.controller'
import { progressRoutes } from './controllers/progress.controller'
import { statsRoutes } from './controllers/stats.controller'
import { thumbRoutes } from './controllers/thumb.controller'
import { translateRoutes } from './controllers/translate.controller'

export function createApp(): Hono<Env> {
  const app = new Hono<Env>()

  app.use('*', cors({
    origin: '*',
    allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowHeaders: ['Content-Type', 'Authorization', 'x-file-name', 'x-book-key'],
  }))

  // públicas
  app.route('', translateRoutes)
  app.route('', authRoutes)

  // protegidas (auth via cookie ou Bearer)
  app.route('', bookRoutes)
  app.route('', progressRoutes)
  app.route('', statsRoutes)
  app.route('', thumbRoutes)

  return app
}
