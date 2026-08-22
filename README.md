# pdf_translate — Monolito (Cloudflare Worker + Flutter)

Monolito com backend e apps nativos a partir do projeto web original.

```
pdf_translate/
├── server/        # Cloudflare Worker (Hono + R2 + KV) — API
│   └── worker.ts  # /api/login, /api/books, /api/progress, /api/stats, /api/translate, /api/thumbs
├── app/           # Flutter (Android, iOS, Web, Windows, Linux, macOS)
│   └── lib/       # auth / library / reader (pdf + tradução + anotações) / stats
├── client/        # Vue legado (web original) — mantido para referência
├── wrangler.toml  # Worker + R2 + KV + assets
└── package.json   # scripts: build / deploy (worker)
```

## Backend

```bash
npm run dev:worker   # worker + client build local
npm run build        # vue-tsc + vite (gera client/dist para assets do Worker)
npm run deploy       # build + wrangler deploy
```

Env (`server/worker.ts`):
- `BOOKS` R2, `PROGRESS` KV, `JWT_SECRET`, `ALLOWED_EMAIL`, `PASSWORD_HASH`
- Local: `.dev.vars`

## Flutter App

```bash
cd app
flutter pub get
flutter run -d chrome        # web
flutter run -d linux         # desktop
flutter run -d android       # device/emulador
```

Features replicadas do web:
- login (JWT cookie -> token via header)
- biblioteca (upload/list/delete + thumb)
- leitor PDF (pdfrx) com seleção + popup tradução (Google gtx proxy)
- anotações (marca-texto/desenho/borracha) salvas localmente
- estatísticas (pages/minutes/highlights por dia + heatmap)
- estimador de tempo livro/capítulo (baseado em outline + ritmo real)

## Migrando do web

Fluxo do app espelha `client/src/`:
`api.ts` → `app/lib/src/api/` • `LibraryView.vue` → `library_screen.dart` • `ReaderView.vue`+`PdfViewer.vue` → `reader_screen.dart` • `StatsView.vue` → `stats_screen.dart`
