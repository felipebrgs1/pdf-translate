# Arquitetura — PDF Translate

## Visão Geral
Monolito **Flutter (raiz)** + **Cloudflare Worker (Hono)**. Flutter é o único front (Linux/Web/Android/iOS); Worker é o único backend. Persistência: **R2** para blobs + **KV** para progresso/stats. Tradução com fallback em 3 camadas. Compressão de PDF no client antes do upload.

---

## Diagrama Geral (ASCII)

```
                          ┌─────────────────────────────────────────┐
                          │           USER (Linux x64)              │
                          │  pdf-translate (Flutter `app` binary)   │
                          │  ~/.local/bin/pdf-translate ->          │
                          │  ~/.local/share/pdf-translate/app       │
                          └──────────────┬──────────────────────────┘
                                         │ HTTPS + JWT Bearer
                                         ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                        CLOUDFLARE WORKER (Hono)                              │
│  https://pdf-translate.felipebrgs.workers.dev                                │
│  wrangler.toml: main=server/worker.ts, assets=build/web                     │
│                                                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │
│  │  auth    │  │  books   │  │ progress │  │  stats   │  │  translate   │  │
│  │ POST     │  │ GET/POST │  │ GET/PUT  │  │ GET/POST │  │ GET          │  │
│  │ /api/login│  │/api/books│  │/api/progress│/api/stats│  │/api/translate│  │
│  │ /api/me  │  │/api/books/:key│  │ :key   │  │        │  │ ?q=&target= │  │
│  │          │  │ DELETE   │  │          │  │          │  │              │  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └──────┬───────┘  │
│       │             │             │             │               │           │
│       │  ┌──────────┴─────────────┴─────────────┴───────────────┘           │
│       │  │                 middleware/auth.ts (JWT)                         │
│       │  │  Bearer <token> -> getUser() -> user = email lowercased          │
│       └──┘                                                                  │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │ Services: auth.service / book.service / stats.service               │    │
│  │  - userPrefix(user) = "email@example.com/"                          │    │
│  │  - quota 150MB por user (soma R2 sem thumbs)                        │    │
│  └────────────────────────────────────────────────────────────────────┘    │
└──────────────┬──────────────────────┬───────────────────┬──────────┬─────────┘
               │                      │                   │          │
               ▼                      ▼                   ▼          ▼
        ┌─────────────┐      ┌─────────────────┐  ┌──────────┐  ┌──────────────────┐
        │  R2: BOOKS  │      │  KV: PROGRESS   │  │  Assets  │  │ External APIs    │
        │ pdf-translate│     │                 │  │ build/web│  │ translate.googleapis│
        │ -books      │      │ progress:<user>:│  │ (Flutter │  │ clients5.google  │
        │             │      │   <key> = {page,│  │  web)    │  │ api.mymemory     │
        │ <user>/     │      │   totalPages,   │  │          │  │                  │
        │  <uuid>.pdf │      │   percent}      │  │          │  └────────┬─────────┘
        │ thumbs/     │      │ stats:<user> =  │  │          │           ▲
        │  <user>/    │      │  {YYYY-MM-DD:   │  │          │           │ fallback
        │   <uuid>.webp│     │   {pages,minutes│  │          │           │ gtx→chrome→mymemory
        └─────────────┘      │   highlights}}  │  └──────────┘           │
                             └─────────────────┘                         │
                                                                         │
               ┌─────────────────────────────────────────────────────────┘
               │
┌──────────────┴─────────────────────────────────────────────────────────────┐
│                        FLUTTER APP (lib/)                                  │
│  main.dart: Provider<Api> + ThemeData.dark + rotas (/ /login /library ...) │
│                                                                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────────┐     │
│  │ auth_gate /  │  │ library_     │  │ reader_screen.dart (pdfrx)   │     │
│  │ login_screen │→ │ screen.dart  │→ │  - pdfrx render + zoom 50-300│     │
│  │ SharedPrefs  │  │ file_picker  │  │  - setas ←→↑↓               │     │
│  │ JWT Bearer   │  │ cached_network│  │  - seleção azul 0x663B82F6  │     │
│  └──────────────┘  │ _image (thumb)│  │  - Api.translate()          │     │
│                    └──────┬───────┘  └──────────┬───────────────────┘     │
│                           │                     │                         │
│                    ┌──────▼───────┐      ┌──────▼────────┐                │
│                    │  pdf_cache   │      │  stats_screen │                │
│                    │  pdf_compress│      │  heatmap      │                │
│                    └──────────────┘      └───────────────┘                │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Componentes

### 1. Flutter App (`lib/`)
| Módulo | Arquivo | Responsabilidade |
|---|---|---|
| **Api** | `lib/src/api/api.dart` | `baseUrl` workers.dev, `Authorization: Bearer`, `loadPersistedToken()`, `listBooks/uploadBook/getBookBytes`, `progress`/`stats`, `translate()` com 3 tentativas |
| **Auth** | `features/auth/*` | `AuthGate` verifica token, `LoginScreen` persiste JWT em `SharedPreferences` |
| **Library** | `features/library/*` | `file_picker` → `compressPdf()` → `POST /api/books` + `makeThumbnail()` → `POST /api/thumbs`, lista via `GET /api/books`, delete |
| **Reader** | `features/reader/*` | `pdfrx` render, zoom, navegação, seleção → tradução, anotações; `GET /api/books/:key` com cache |
| **Stats** | `features/stats/*` | `GET /api/stats` heatmap, `POST /api/stats` a cada leitura |
| **Cache** | `src/cache/pdf_cache.dart` | `getApplicationDocumentsDirectory()/pdf_cache/<key>.pdf`, `savePdfToCache/isPdfCached` |
| **Compress** | `src/cache/pdf_compress.dart` | `compressPdf()` — ver §4 |

### 2. Worker (`server/`)
```
server/src/app.ts              # Hono + CORS (*), monta rotas
server/src/middleware/auth.ts  # extrai JWT, getUser()
server/src/controllers/        # auth | book | progress | stats | thumb | translate
server/src/services/           # book.service (quota, list), stats.service, auth.service
server/src/models/types.ts     # Env bindings, STORAGE_QUOTA=150MB
wrangler.toml                  # R2_BOOKS, KV_PROGRESS, assets=build/web
```

### 3. Storage

**R2 `BOOKS` (`pdf-translate-books`):**
```
felipe@gmail.com/<uuid>.pdf          # legado sem prefixo (compat)
<user>/ <uuid>.pdf                   # novo: isolado por email lowercased
thumbs/<user>/<uuid>.webp            # thumbnail 300x400 jpg→webp, 80% quality
```
- `customMetadata: {name}` guarda nome original
- `checkQuota()` soma `size` de todos objetos com prefixo (ignora thumbs) → 413 se >150MB
- compat: `felipe@gmail.com` ainda lê chaves sem `/`

**KV `PROGRESS` (`be64f793...`):**
```
progress:<user>:<key>  →  {"page":12,"totalPages":200,"percent":6.0,"updatedAt":"..."}
stats:<user>           →  {"2026-08-20":{"pages":30,"minutes":45,"highlights":5}, ...}
```

---

## Fluxos Principais

### Upload (com compressão)
```
[FilePicker] → bytes (Uint8List)
     │
     ▼ compressPdf()
     ├─ <100KB → skip
     ├─ _lossless(): PdfDocument(compressionLevel=best).save()  → se economiza >2% usa
     └─ se >3MB: _recompressImages()
          ├─ varre PDF raw: procura streams /Subtype /Image + /DCTDecode ou /FlateDecode
          ├─ ignora Predictor !=1, <50x50, CMYK sem decode
          ├─ JPEG: decodeJpg → resize (max 1200, >600 → *0.65) → encodeJpg(quality 70)
          ├─ Flate: ZLibDecoder → DeviceRGB/Gray → rgb → encodeJpg 70
          ├─ reescreve dict: /Filter /DCTDecode, /Width/Height, /Length, remove DecodeParms
          └─ só aplica se saved >100KB e processou ≥1 imagem
     │
     ▼ POST /api/books (header x-file-name, body pdf, Bearer)
     → Worker checkQuota → R2 put <user>/<uuid>.pdf
     │
     ▼ makeThumbnail(pdfBytes)  [pdfrx page.render 300x400 → png → decodePng → encodeJpg 80]
     → POST /api/thumbs (header x-book-key, body webp)
     → R2 put thumbs/<key>.webp
```

### Leitura
```
Library tap → GET /api/books/:key (Bearer)
           → Worker valida prefixo ownership → R2 get → 200 pdf bytes
           → savePdfToCache(key, bytes) → pdf_cache/<key>.pdf
           → PdfDocument.openData → pdfrx render
           → a cada troca página: PUT /api/progress/:key {page,totalPages} → KV
           → background: POST /api/stats {date,pages,minutes}
Thumb: GET /api/thumbs/:key → R2 thumbs/...webp (Cache-Control 86400) → CachedNetworkImage
Cache hit: isPdfCached(key) → File read → sem rede
```

### Tradução (3 camadas)
```
Flutter Api.translate(q, target):
  1. _translateDirect: GET https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=pt&dt=t&q=...
     → parse d[0][0]  (3 tentativas, sleep 300ms)
  2. _translateMyMemory: GET https://api.mymemory.translated.net/get?q=...&langpair=auto|pt
     → responseData.translatedText
  3. _translateViaProxy: GET /api/translate?q=&target= (Bearer)
     Worker translate.controller:
        a) translateGtx (gtx, 3 tentativas)
        b) translateChromeEx (clients5.google.com/translate_a/t?client=dict-chrome-ex)
        c) translateMyMemory (mymemory)
        → {translated, source, target} ou 502
```

### Stats
```
GET /api/stats → readDailyStats(KV stats:<user>) → {days:{YYYY-MM-DD:{pages,minutes,highlights}}}
POST /api/stats {date,pages,minutes,highlights} → clampCount + merge → writeDailyStats(KV)
Reader chama addStats() a cada progresso / highlight
```

---

## Build & Deploy

```
 git tag v1.0.0 ──► push ──► GitHub Actions (.github/workflows/release.yml)
                              ├── ubuntu-22.04 + libgtk-3-dev
                              ├── subosito/flutter-action (stable)
                              ├── flutter build linux --release --build-name=1.0.0 --build-number=N
                              │     → build/linux/x64/release/bundle/{app, lib/, data/flutter_assets}
                              ├── tar -czf pdf-translate-v1.0.0-linux-x64.tar.gz -C bundle .
                              ├── zip + sha256
                              ├── dpkg-deb: /opt/pdf-translate + /usr/bin/pdf-translate + .desktop
                              └── softprops/action-gh-release → Release + assets

 User: curl -fsSL .../install.sh | bash
        ├── resolve latest via redirect ou api.github.com
        ├── curl -L .../releases/download/v1.0.0/pdf-translate-...tar.gz + .sha256
        ├── sha256sum -c
        ├── tar -xzf → ~/.local/share/pdf-translate  (ou /opt com --system)
        ├── wrapper ~/.local/bin/pdf-translate → exec $PREFIX/app
        └── .desktop → ~/.local/share/applications/pdf-translate.desktop
```

---

## Decisões de Arquitetura

- **Single Worker** em vez de backend separado: custo zero (free tier), cold start <50ms, R2/KV nativos.
- **Prefixo por usuário** no R2/KV: multi-tenancy sem DB; quota 150MB evita abuso; legado `felipe@gmail.com` sem prefixo mantido por compatibilidade.
- **Compressão no client** (não no Worker): Worker tem limite 100MB / 30s CPU; `syncfusion_flutter_pdf` + `archive` + `image` fazem lossless + recompress JPEG 70% preservando texto vetorial (≠ rasterizar página).
- **Cache em disco** (`pdf_cache`): evita re-download de PDFs grandes; thumbnail separado em R2 evita re-render.
- **Tradução em cascata**: direta do app evita latência do Worker; fallback via Worker contorna CORS/rate-limit no web; MyMemory como último recurso gratuito.
- **Binary `app`** (BINARY_NAME em linux/CMakeLists.txt): nome estável para wrapper e .deb; `flutter_assemble` + `APPLICATION_ID com.example.app`.

---

## Limites & Próximos Passos
- Quota 150MB hard-coded em `types.ts` + `book.service.ts` — extrair para env var.
- Auth single `ALLOWED_EMAIL` legado → migrar para KV `users:{email}` com hash.
- Thumbs `.webp` mas gerados como JPG 80 — unificar para `image/webp`.
- Adicionar `GET /api/books/:key?range` para streaming de PDFs >50MB.
- CI: adicionar `flutter test` + `wrangler --dry-run` no PR.
