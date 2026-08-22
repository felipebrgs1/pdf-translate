<p align="center">
  <img src="assets/icon/app_icon.png" width="120" alt="PDF Translate" />
</p>

<h1 align="center">PDF Translate</h1>
<p align="center">
  <b>Leia. Traduza. Anote. Evolua.</b><br/>
  Leitor de PDF minimalista com tradução instantânea, anotações e estatísticas de leitura.
</p>

<p align="center">
  <a href="https://github.com/felipebrgs1/pdf-translate/releases"><img src="https://img.shields.io/github/v/release/felipebrgs1/pdf-translate?label=vers%C3%A3o&color=0ea5e9" alt="release"/></a>
  <a href="https://github.com/felipebrgs1/pdf-translate/actions/workflows/release.yml"><img src="https://github.com/felipebrgs1/pdf-translate/actions/workflows/release.yml/badge.svg" alt="build"/></a>
  <img src="https://img.shields.io/badge/plataforma-linux%20x64-24292e" alt="linux"/>
  <img src="https://img.shields.io/badge/feito%20com-Flutter-02569B?logo=flutter" alt="flutter"/>
</p>

<p align="center">
  <a href="#-instalação-em-10-segundos">Instalação</a> •
  <a href="#-como-usar">Como usar</a> •
  <a href="#-atalhos">Atalhos</a> •
  <a href="#-atualizar-e-desinstalar">Atualizar</a> •
  <a href="#-faq">FAQ</a>
</p>

---

## ✨ Por que usar?

| | |
|---|---|
| 📖 **Leitor rápido** | PDF nativo com `pdfrx`, zoom 50–300%, navegação fluida |
| 🌐 **Tradução na seleção** | Selecione qualquer trecho e traduza na hora |
| ✏️ **Anotações** | Grife e anote sem sair do livro |
| 📊 **Estatísticas reais** | Heatmap de leitura, tempo por livro/capítulo, estimativa de término |
| ☁️ **Biblioteca na nuvem** | Upload, thumbnails e progresso sincronizados (Cloudflare R2 + KV) |
| 🔒 **Só seu** | Login com JWT, cada usuário vê só seus livros (isolamento por prefixo) |

> Feito para quem lê PDF todo dia — artigo, manual, livro técnico — e quer entender sem fricção.

---

## 🚀 Instalação em 10 segundos

### Opção 1 — Uma linha (recomendado)
```bash
curl -fsSL https://raw.githubusercontent.com/felipebrgs1/pdf-translate/main/install.sh | bash
```
Pronto. O app estará em `~/.local/bin/pdf-translate`.

Abra o menu do sistema e busque **"PDF Translate"** ou rode no terminal:
```bash
pdf-translate
```

### Opção 2 — Baixar manualmente
1. Vá em [**Releases**](https://github.com/felipebrgs1/pdf-translate/releases) e baixe o arquivo da última versão:
   - `pdf-translate-v1.0.0-linux-x64.tar.gz` (portátil)
   - `pdf-translate-v1.0.0-linux-x64.deb` (instalador Debian/Ubuntu)
   - `pdf-translate-v1.0.0-linux-x64.zip`

2. **.deb (Ubuntu/Debian):**
   ```bash
   sudo dpkg -i pdf-translate-v*.deb
   # ou pelo instalador:
   curl -fsSL https://raw.githubusercontent.com/felipebrgs1/pdf-translate/main/install.sh | bash -s -- --deb
   ```

3. **.tar.gz (qualquer distro):**
   ```bash
   tar -xzf pdf-translate-v*.tar.gz -C ~/.local/share/pdf-translate
   ~/.local/share/pdf-translate/app
   ```

### Outras formas
```bash
# versão específica
curl -fsSL https://raw.githubusercontent.com/felipebrgs1/pdf-translate/main/install.sh | bash -s -- --version v1.0.0

# instalar em /opt (requer sudo, cria atalho em /usr/local/bin)
curl -fsSL https://raw.githubusercontent.com/felipebrgs1/pdf-translate/main/install.sh | bash -s -- --system

# pasta custom
PREFIX=$HOME/apps/pdf-translate BIN_DIR=$HOME/.local/bin bash install.sh
```

> **Requisitos:** distro com `libgtk-3-0` (Ubuntu 22.04+, Fedora, Arch já têm). O script cuida do resto.

---

## 🧭 Como usar

### 1. Login
Abra o app → informe e-mail e senha configurados no Worker. O token fica salvo com segurança.

### 2. Biblioteca
- **Adicionar:** arraste um PDF ou clique em *Upload*
- **Abrir:** clique na capa (thumbnail gerada automaticamente)
- **Remover:** menu `⋮` → *Excluir*
- Tudo fica sincronizado — pode trocar de máquina e seus livros continuam lá.

### 3. Leitor
- **Zoom:** `Ctrl +` / `Ctrl -` ou `50%–300%` na barra superior
- **Navegação:** setas `← → ↑ ↓`, `PageUp/PageDown` ou rolagem
- **Seleção:** arraste o texto — ele fica **azul bem visível** (corrigido para tema escuro)
- **Tradução:** selecione → painel de tradução abre automaticamente (fallback resiliente: direct → MyMemory → proxy)
- **Anotações:** destaque e comente trechos importantes
- **Progresso:** salvo automaticamente, continue de onde parou em qualquer dispositivo

### 4. Estatísticas
Menu **Stats** → heatmap de leitura, tempo por dia/livro, estimativa de término por livro e capítulo.

---

## ⌨️ Atalhos

| Atalho | Ação |
|---|---|
| `←` `→` | Página anterior / próxima |
| `↑` `↓` | Rolar |
| `Ctrl +` `Ctrl -` | Zoom in / out |
| `Ctrl 0` | Zoom 100% |
| `F` | Tela cheia (quando disponível) |
| Seleção com mouse | Abre tradução |

---

## 🔄 Atualizar e desinstalar

**Atualizar** — rode o mesmo comando de instalação, ele pega a última versão:
```bash
curl -fsSL https://raw.githubusercontent.com/felipebrgs1/pdf-translate/main/install.sh | bash
```

**Desinstalar (instalação padrão):**
```bash
rm -rf ~/.local/share/pdf-translate ~/.local/bin/pdf-translate ~/.local/share/applications/pdf-translate.desktop
```

**Desinstalar (.deb):**
```bash
sudo dpkg -r pdf-translate
```

**Desinstalar (system):**
```bash
sudo rm -rf /opt/pdf-translate /usr/local/bin/pdf-translate
```

---

## ❓ FAQ

**Não abre? Falta `libgtk-3-0`?**
```bash
sudo apt update && sudo apt install -y libgtk-3-0 libblkid1 liblzma5
```

**Onde ficam meus PDFs?**  
Na nuvem (Cloudflare R2), com isolamento por usuário. Nada fica só local — você não perde ao formatar.

**Funciona offline?**  
Leitura e cache de PDFs recentes funcionam offline. Upload/tradução/stats precisam de internet.

**Como reportar bug ou pedir feature?**  
Abra uma [Issue](https://github.com/felipebrgs1/pdf-translate/issues) com print e versão (`pdf-translate --version` ou `vX.Y.Z` da Release).

**É gratuito?**  
Sim, código aberto. Você só paga o Workers/R2 se hospedar seu próprio backend (plano free cobre uso pessoal).

---

## 🛠️ Para desenvolvedores

<details>
<summary><b>Clique para expandir — stack, env e comandos</b></summary>

```
pdf_translate/           # Flutter na raiz
├── lib/                 # app: auth / library / reader (pdfrx) / stats
├── android/ ios/ web/ linux/ windows/ macos/
├── server/              # Cloudflare Worker (Hono + R2 + KV)
│   └── worker.ts        # /api/login, /api/books, /api/progress, /api/stats, /api/translate, /api/thumbs
├── wrangler.toml
└── package.json
```

**Backend (Worker):**
```bash
npm run dev:server   # tsx watch server/index.ts
npm run build        # flutter build web → build/web (assets do Worker)
npm run deploy       # build + wrangler deploy
npm run dev:worker   # build + wrangler dev
```
Env em `server/worker.ts`: `BOOKS` (R2), `PROGRESS` (KV), `JWT_SECRET`, `ALLOWED_EMAIL`, `PASSWORD_HASH` — local em `.dev.vars`.

**App Flutter:**
```bash
flutter pub get
flutter run -d linux
flutter run -d chrome
flutter run -d android
```

**Release automática (Linux):**
- Workflow `.github/workflows/release.yml` dispara em toda tag `v*.*.*`
- Gera `tar.gz` + `zip` + `.deb` + `sha256` e publica na Release
- Para lançar nova versão:
  ```bash
  git tag v1.0.1
  git push origin v1.0.1
  ```
- Acompanhe em [Actions](https://github.com/felipebrgs1/pdf-translate/actions)

</details>

---

<p align="center">
  Feito com Flutter + Cloudflare • <a href="https://github.com/felipebrgs1/pdf-translate/releases">Baixar última versão</a>
</p>
