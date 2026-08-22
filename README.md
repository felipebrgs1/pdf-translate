# pdf_translate — Monolito Flutter + Worker

```
pdf_translate/           # Flutter na raiz (pubspec.yaml, lib/, android/, ios/, web/...)
├── lib/                 # app Flutter: auth / library / reader (pdfrx + tradução + anotações) / stats
├── android/ ios/ web/ linux/ windows/ macos/
├── test/
├── server/              # Cloudflare Worker (Hono + R2 + KV) — único backend
│   └── worker.ts        # /api/login, /api/books, /api/progress, /api/stats, /api/translate, /api/thumbs
├── wrangler.toml        # Worker + R2 + KV + assets (build/web)
└── package.json         # scripts do Worker
```

> `client/` (Vue) removido — Flutter agora é o front único na raiz.

## Backend

```bash
npm run dev:server   # tsx watch server/index.ts
npm run build        # flutter build web (gera build/web para assets do Worker)
npm run deploy       # build + wrangler deploy
npm run dev:worker   # build + wrangler dev
```

Env (`server/worker.ts`): `BOOKS` R2, `PROGRESS` KV, `JWT_SECRET`, `ALLOWED_EMAIL`, `PASSWORD_HASH` — local em `.dev.vars`

## App Flutter

```bash
flutter pub get
flutter run -d chrome        # web
flutter run -d linux         # desktop
flutter run -d android       # device/emulador
flutter run -d ios
```

Features: login (JWT Bearer + SharedPreferences), biblioteca (upload/list/delete + thumb autenticada), leitor PDF (pdfrx) com zoom 50-300% e setas ←/→/↑/↓, tradução, anotações, estatísticas (heatmap), estimador livro/capítulo.
