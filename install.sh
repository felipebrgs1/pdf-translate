#!/usr/bin/env bash
# PDF Translate - Instalador Linux via bash
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/felipebrgs1/pdf-translate/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/felipebrgs1/pdf-translate/main/install.sh | bash -s -- --version v1.0.0
#   curl -fsSL https://raw.githubusercontent.com/felipebrgs1/pdf-translate/main/install.sh | PREFIX=$HOME/.local bash
#
# Opções:
#   --version vX.Y.Z   instala versão específica (default: latest)
#   --prefix PATH      diretório de instalação (default: $HOME/.local/share/pdf-translate)
#   --bin-dir PATH     diretório do binário/symlink (default: $HOME/.local/bin)
#   --system           instala em /opt/pdf-translate e /usr/local/bin (requer sudo)
#   --deb              instala via .deb (requer sudo + apt/dpkg)
#   --help             mostra ajuda

set -euo pipefail

REPO="felipebrgs1/pdf-translate"
APP_NAME="pdf-translate"
DEFAULT_PREFIX="$HOME/.local/share/pdf-translate"
DEFAULT_BIN_DIR="$HOME/.local/bin"

VERSION="latest"
PREFIX=""
BIN_DIR=""
USE_SYSTEM=false
USE_DEB=false

# parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version|-v) VERSION="$2"; shift 2 ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --bin-dir) BIN_DIR="$2"; shift 2 ;;
    --system) USE_SYSTEM=true; shift ;;
    --deb) USE_DEB=true; shift ;;
    --help|-h)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *) echo "Opção desconhecida: $1" >&2; exit 1 ;;
  esac
done

if [[ "$USE_SYSTEM" == true ]]; then
  PREFIX="/opt/pdf-translate"
  BIN_DIR="/usr/local/bin"
  USE_DEB=false
fi

if [[ -z "$PREFIX" ]]; then
  PREFIX="$DEFAULT_PREFIX"
fi
if [[ -z "$BIN_DIR" ]]; then
  BIN_DIR="$DEFAULT_BIN_DIR"
fi

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Erro: '$1' não encontrado. Instale e tente novamente." >&2; exit 1; }; }

need_cmd curl
need_cmd tar

# detecta arch
ARCH="x64"
MACHINE="$(uname -m)"
case "$MACHINE" in
  x86_64|amd64) ARCH="x64" ;;
  *) echo "Aviso: arquitetura $MACHINE pode não ser suportada, tentando x64" >&2 ;;
esac

# resolve versão latest
if [[ "$VERSION" == "latest" ]]; then
  echo "→ Buscando última release de $REPO..."
  # tenta via redirect (sem API, sem rate limit)
  if command -v curl >/dev/null; then
    REDIRECT_URL=$(curl -fsSI "https://github.com/${REPO}/releases/latest" | tr -d '\r' | grep -i "^location:" | tail -1 | awk '{print $2}')
    if [[ -n "$REDIRECT_URL" ]]; then
      VERSION=$(basename "$REDIRECT_URL")
    fi
  fi
  # fallback via API
  if [[ "$VERSION" == "latest" || -z "$VERSION" ]]; then
    VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)
  fi
  if [[ -z "$VERSION" ]]; then
    echo "Erro: não foi possível resolver a versão latest" >&2
    exit 1
  fi
  echo "→ Última versão: $VERSION"
fi

# normaliza: garante prefixo v
if [[ "$VERSION" != v* ]]; then
  VERSION="v${VERSION}"
fi

echo "→ Instalando $APP_NAME $VERSION para linux-$ARCH"
echo "  PREFIX=$PREFIX"
echo "  BIN_DIR=$BIN_DIR"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# modo .deb
if [[ "$USE_DEB" == true ]]; then
  need_cmd dpkg
  DEB_NAME="${APP_NAME}-${VERSION}-linux-${ARCH}.deb"
  DEB_URL="https://github.com/${REPO}/releases/download/${VERSION}/${DEB_NAME}"
  echo "→ Baixando $DEB_URL"
  curl -fL --progress-bar -o "$TMPDIR/$DEB_NAME" "$DEB_URL"
  echo "→ Instalando .deb (requer sudo)..."
  sudo dpkg -i "$TMPDIR/$DEB_NAME" || sudo apt-get install -f -y
  echo "✔ Instalado via .deb. Execute: pdf-translate"
  exit 0
fi

# modo tar.gz
TARBALL="${APP_NAME}-${VERSION}-linux-${ARCH}.tar.gz"
URL="https://github.com/${REPO}/releases/download/${VERSION}/${TARBALL}"
SHA_URL="${URL}.sha256"

echo "→ Baixando $URL"
if ! curl -fL --progress-bar -o "$TMPDIR/$TARBALL" "$URL"; then
  echo "Erro: falha ao baixar $URL" >&2
  echo "Verifique se a tag $VERSION existe em https://github.com/${REPO}/releases" >&2
  exit 1
fi

# verifica sha256 se disponível
if curl -fsSL -o "$TMPDIR/$TARBALL.sha256" "$SHA_URL" 2>/dev/null; then
  echo "→ Verificando checksum..."
  if command -v sha256sum >/dev/null; then
    (cd "$TMPDIR" && sha256sum -c "$TARBALL.sha256")
  elif command -v shasum >/dev/null; then
    (cd "$TMPDIR" && shasum -a 256 -c "$TARBALL.sha256")
  fi
fi

echo "→ Extraindo para $PREFIX ..."
mkdir -p "$PREFIX"
# se for instalação system, precisa sudo
if [[ "$PREFIX" == /opt/* ]]; then
  sudo mkdir -p "$PREFIX"
  sudo tar -xzf "$TMPDIR/$TARBALL" -C "$PREFIX" --strip-components=0 2>/dev/null || sudo tar -xzf "$TMPDIR/$TARBALL" -C "$PREFIX"
  sudo chmod +x "$PREFIX/app" 2>/dev/null || true
else
  tar -xzf "$TMPDIR/$TARBALL" -C "$PREFIX" --strip-components=0 2>/dev/null || tar -xzf "$TMPDIR/$TARBALL" -C "$PREFIX"
  chmod +x "$PREFIX/app" 2>/dev/null || true
fi

# cria wrapper/symlink
mkdir -p "$BIN_DIR" 2>/dev/null || sudo mkdir -p "$BIN_DIR"
WRAPPER="$BIN_DIR/pdf-translate"

# encontra binário
BIN_CANDIDATE="$PREFIX/app"
if [[ ! -f "$BIN_CANDIDATE" ]]; then
  # procura recursivo
  BIN_CANDIDATE=$(find "$PREFIX" -maxdepth 3 -name "app" -type f | head -1)
fi

if [[ "$BIN_DIR" == /usr/local/bin || "$PREFIX" == /opt/* ]]; then
  sudo tee "$WRAPPER" >/dev/null <<EOF
#!/bin/sh
exec "$BIN_CANDIDATE" "\$@"
EOF
  sudo chmod +x "$WRAPPER"
else
  cat > "$WRAPPER" <<EOF
#!/bin/sh
exec "$BIN_CANDIDATE" "\$@"
EOF
  chmod +x "$WRAPPER"
fi

# .desktop
DESKTOP_DIR="$HOME/.local/share/applications"
mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP_DIR/pdf-translate.desktop" <<EOF
[Desktop Entry]
Name=PDF Translate
Comment=Leitor de PDF com tradução
Exec=$WRAPPER
Icon=pdf-translate
Terminal=false
Type=Application
Categories=Office;Viewer;
StartupWMClass=pdf_translate
EOF

# verifica PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo ""
  echo "⚠  $BIN_DIR não está no PATH."
  echo "   Adicione ao seu ~/.bashrc ou ~/.zshrc:"
  echo "   export PATH=\"\$PATH:$BIN_DIR\""
fi

echo ""
echo "✔ Instalado com sucesso!"
echo "  Binário: $BIN_CANDIDATE"
echo "  Atalho : $WRAPPER"
echo "  Execute: pdf-translate  (ou $WRAPPER)"
echo ""
echo "Para desinstalar: rm -rf \"$PREFIX\" \"$WRAPPER\" \"$DESKTOP_DIR/pdf-translate.desktop\""
