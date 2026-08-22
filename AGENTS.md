# AGENTS.md — Guia para Agents

> Monolito Flutter (raiz) + Cloudflare Worker. Leia antes de codar.

## 1. Visão Geral
App de leitura PDF com tradução, anotações, biblioteca e stats. Flutter é o front único (antes havia `client/` Vue). Worker `server/worker.ts` é o único backend (R2+KV). Tema escuro, seleção azul visível.

## 2. Stack
- **App:** Flutter 3.47 / Dart 3.13 — `pdfrx`, `provider`, `shared_preferences`, `file_picker`, `cached_network_image`, `syncfusion_flutter_pdf`
- **Backend:** Cloudflare Worker (Hono) + R2 (`BOOKS`) + KV (`PROGRESS`) + `wrangler.toml`
- **Build Linux:** `flutter build linux` (binary `app`), empacotado em `tar.gz`/`deb` via Actions

## 3. Estrutura
```
./lib/main.dart              # entry, Provider<Api>, rotas
./lib/src/api/api.dart       # Api client (JWT Bearer)
./lib/src/features/auth|library|reader|stats
./lib/src/cache/             # pdf_cache, compress
./server/worker.ts           # /api/login, /books, /progress, /stats, /translate, /thumbs (MVC)
./assets/icon/app_icon.png
./.github/workflows/release.yml
./install.sh                 # instalador bash
```

## 4. Comandos Essenciais
```bash
flutter pub get
flutter run -d linux          # ou -d chrome
flutter analyze && flutter test
flutter build linux --release --build-name=1.0.0 --build-number=1

npm run dev:server            # tsx watch server/index.ts
flutter build web && wrangler dev   # Worker local
flutter build web && wrangler deploy
./install.sh --help
```

## 5. Convenções
- **Flutter:** `provider` para estado, `SharedPreferences` p/ token, Material dark + `ThemeData` em `main.dart`. Não quebrar zoom 50-300% e navegação setas.
- **PDF:** `pdfrx` obrigatório. Seleção deve manter `selectionColor: 0x663B82F6` (azul visível).
- **API:** sempre `Authorization: Bearer <JWT>`, isolamento por prefixo de usuário no R2/KV.
- **Commits:** `feat:`, `fix:`, `refactor:`, `docs:` em pt-BR ou en. Sem `pubspec.lock` manual.
- **Não** recriar `client/` (removido), não mudar `BINARY_NAME=app` em `linux/CMakeLists.txt`.

## 6. Worker (`server/worker.ts`)
- Rotas: `POST /api/login`, `GET|POST|DELETE /api/books`, `GET /api/thumbs/:id`, `GET|PUT /api/progress`, `GET /api/stats`, `POST /api/translate`.
- Env: `BOOKS` (R2), `PROGRESS` (KV), `JWT_SECRET`, `ALLOWED_EMAIL`, `PASSWORD_HASH` (em `.dev.vars` local).
- Tradução: fallback `direct -> mymemory -> proxy` — manter resiliente.

## 7. App — Pontos Críticos
- `lib/src/api/api.dart`: `loadPersistedToken()`, intercepta 401 → login.
- `reader_screen.dart`: pdfrx + zoom + setas ←→↑↓ + painel tradução + anotações.
- `library_screen.dart`: upload/list/delete + thumb autenticada.
- `stats_screen.dart`: heatmap + estimador.

## 8. Release / Deploy Linux
- Workflow: `.github/workflows/release.yml` — trigger `push` tag `v*.*.*` + `workflow_dispatch`.
- Gera `pdf-translate-vX.Y.Z-linux-x64.{tar.gz,zip,deb}+sha256` em `dist/` e publica Release via `softprops/action-gh-release`.
- Lançar:
  ```bash
  git tag v1.0.1 && git push origin v1.0.1
  gh run watch && gh release view v1.0.1
  ```
- Instalador: `install.sh` (flags `--version`, `--system`, `--deb`, `--prefix`, `--bin-dir`).

## 9. Do / Don't
- ✅ Rode `flutter analyze` antes de commit. Teste `flutter build linux` se mexer em `linux/`.
- ✅ Mantenha `install.sh` POSIX + `set -euo pipefail`, teste com `bash -n`.
- ✅ Atualize `README.md` se mudar instalação/atalhos.
- ❌ Não commitar `.dev.vars`, `build/`, `.dart_tool/`, segredos.
- ❌ Não alterar `wrangler.toml` assets sem `flutter build web` antes.
- ❌ Não usar `npm run deploy` sem checar `ALLOWED_EMAIL/PASSWORD_HASH`.

## 10. Troubleshooting
- `libgtk-3-0` faltando: `sudo apt install libgtk-3-dev libblkid-dev liblzma-dev`
- Token expirado: limpar `SharedPreferences` ou relogar.
- Thumb 401: verificar `Authorization` header no `cached_network_image`.

---
*Dúvidas? Veja `README.md` (usuário) e `server/worker.ts` (contrato API).*
