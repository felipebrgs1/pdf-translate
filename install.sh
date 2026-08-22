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
APP_ID="dev.felipebrgs.pdftranslate"
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
  if command -v curl >/dev/null; then
    REDIRECT_URL=$(curl -fsSI "https://github.com/${REPO}/releases/latest" | tr -d '\r' | grep -i "^location:" | tail -1 | awk '{print $2}')
    if [[ -n "$REDIRECT_URL" ]]; then
      VERSION=$(basename "$REDIRECT_URL")
    fi
  fi
  if [[ "$VERSION" == "latest" || -z "$VERSION" ]]; then
    VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)
  fi
  if [[ -z "$VERSION" ]]; then
    echo "Erro: não foi possível resolver a versão latest" >&2
    exit 1
  fi
  echo "→ Última versão: $VERSION"
fi

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
  # atualiza desktop db
  update-desktop-database ~/.local/share/applications 2>/dev/null || true
  sudo update-desktop-database /usr/share/applications 2>/dev/null || true
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
if [[ "$PREFIX" == /opt/* ]]; then
  sudo mkdir -p "$PREFIX"
  sudo tar -xzf "$TMPDIR/$TARBALL" -C "$PREFIX" --strip-components=0 2>/dev/null || sudo tar -xzf "$TMPDIR/$TARBALL" -C "$PREFIX"
  # binário novo é pdf-translate, compat com app antigo
  if [[ -f "$PREFIX/pdf-translate" ]]; then sudo chmod +x "$PREFIX/pdf-translate"; fi
  if [[ -f "$PREFIX/app" ]]; then sudo chmod +x "$PREFIX/app"; fi
else
  tar -xzf "$TMPDIR/$TARBALL" -C "$PREFIX" --strip-components=0 2>/dev/null || tar -xzf "$TMPDIR/$TARBALL" -C "$PREFIX"
  chmod +x "$PREFIX/pdf-translate" 2>/dev/null || true
  chmod +x "$PREFIX/app" 2>/dev/null || true
fi

# encontra binário (novo nome primeiro, fallback legado)
BIN_CANDIDATE=""
for cand in "$PREFIX/pdf-translate" "$PREFIX/app"; do
  if [[ -f "$cand" ]]; then BIN_CANDIDATE="$cand"; break; fi
done
if [[ -z "$BIN_CANDIDATE" ]]; then
  BIN_CANDIDATE=$(find "$PREFIX" -maxdepth 3 -name "pdf-translate" -type f 2>/dev/null | head -1)
  if [[ -z "$BIN_CANDIDATE" ]]; then
    BIN_CANDIDATE=$(find "$PREFIX" -maxdepth 3 -name "app" -type f 2>/dev/null | head -1)
  fi
fi
if [[ -z "$BIN_CANDIDATE" ]]; then
  echo "Erro: binário não encontrado em $PREFIX" >&2
  ls -R "$PREFIX" | head -30
  exit 1
fi
echo "→ Binário: $BIN_CANDIDATE"

# cria wrapper
mkdir -p "$BIN_DIR" 2>/dev/null || sudo mkdir -p "$BIN_DIR"
WRAPPER="$BIN_DIR/pdf-translate"
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

# instala ícone
ICON_SRC=""
# tenta pegar do bundle (se houver) ou baixa do repo
if [[ -f "$TMPDIR/icon.png" ]]; then
  ICON_SRC="$TMPDIR/icon.png"
fi
# baixa do repo (sempre tenta manter atualizado)
echo "→ Instalando ícone..."
ICON_URL="https://raw.githubusercontent.com/${REPO}/main/assets/icon/app_icon.png"
curl -fsSL -o "$TMPDIR/app_icon.png" "$ICON_URL" 2>/dev/null || true
if [[ -f "$TMPDIR/app_icon.png" ]]; then
  ICON_SRC="$TMPDIR/app_icon.png"
fi

# instala em hicolor (user ou system)
if [[ "$PREFIX" == /opt/* || "$BIN_DIR" == /usr/local/bin ]]; then
  sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
  sudo mkdir -p /usr/share/icons/hicolor/256x256/apps
  sudo mkdir -p /usr/share/pixmaps
  if [[ -n "$ICON_SRC" ]]; then
    sudo cp "$ICON_SRC" /usr/share/icons/hicolor/512x512/apps/pdf-translate.png
    sudo cp "$ICON_SRC" /usr/share/icons/hicolor/256x256/apps/pdf-translate.png
    sudo cp "$ICON_SRC" /usr/share/pixmaps/pdf-translate.png
  fi
  sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
else
  mkdir -p "$HOME/.local/share/icons/hicolor/512x512/apps"
  mkdir -p "$HOME/.local/share/icons/hicolor/256x256/apps"
  mkdir -p "$HOME/.local/share/pixmaps"
  if [[ -n "$ICON_SRC" ]]; then
    cp "$ICON_SRC" "$HOME/.local/share/icons/hicolor/512x512/apps/pdf-translate.png"
    cp "$ICON_SRC" "$HOME/.local/share/icons/hicolor/256x256/apps/pdf-translate.png"
    cp "$ICON_SRC" "$HOME/.local/share/pixmaps/pdf-translate.png" 2>/dev/null || true
  fi
  gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
fi

# .desktop — com APP_ID correto para Wayland
DESKTOP_DIR="$HOME/.local/share/applications"
if [[ "$PREFIX" == /opt/* ]]; then
  DESKTOP_DIR="/usr/share/applications"
  # também cria no user para garantir visibilidade
  mkdir -p "$HOME/.local/share/applications"
fi
mkdir -p "$DESKTOP_DIR" 2>/dev/null || sudo mkdir -p "$DESKTOP_DIR"

DESKTOP_FILE="$DESKTOP_DIR/pdf-translate.desktop"
# desktop id deve bater com APPLICATION_ID para Wayland
DESKTOP_ID_FILE="$DESKTOP_DIR/${APP_ID}.desktop"

for DF in "$DESKTOP_FILE" "$DESKTOP_ID_FILE"; do
  if [[ "$DF" == /usr/* ]]; then
    sudo tee "$DF" >/dev/null <<EOF
[Desktop Entry]
Name=PDF Translate
GenericName=Leitor de PDF
Comment=Leitor de PDF com tradução, anotações e estatísticas
Exec=$WRAPPER %U
Icon=pdf-translate
Terminal=false
Type=Application
Categories=Office;Viewer;Education;
Keywords=pdf;translate;leitor;
StartupWMClass=$APP_ID
StartupNotify=true
MimeType=application/pdf;
EOF
  else
    cat > "$DF" <<EOF
[Desktop Entry]
Name=PDF Translate
GenericName=Leitor de PDF
Comment=Leitor de PDF com tradução, anotações e estatísticas
Exec=$WRAPPER %U
Icon=pdf-translate
Terminal=false
Type=Application
Categories=Office;Viewer;Education;
Keywords=pdf;translate;leitor;
StartupWMClass=$APP_ID
StartupNotify=true
MimeType=application/pdf;
EOF
  fi
done

# remove desktop legado com WMClass errado
if [[ -f "$HOME/.local/share/applications/pdf-translate.desktop" ]]; then
  # já recriado acima com valor correto, só garante permissão
  chmod +x "$HOME/.local/share/applications/pdf-translate.desktop" 2>/dev/null || true
  chmod +x "$HOME/.local/share/applications/${APP_ID}.desktop" 2>/dev/null || true
fi

# atualiza desktop database
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
if [[ "$DESKTOP_DIR" == /usr/* ]]; then
  sudo update-desktop-database /usr/share/applications 2>/dev/null || true
fi

# limpa desktop legado com ícone quebrado (se StartupWMClass antigo)
if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$DESKTOP_FILE" 2>&1 | head -5 || true
fi

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
echo "  Ícone  : pdf-translate (hicolor 512x512)"
echo "  Desktop: $DESKTOP_FILE + $DESKTOP_ID_FILE"
echo "  App ID : $APP_ID (Wayland)"
echo "  Execute: pdf-translate  (ou $WRAPPER)"
echo ""
echo "Se o ícone não aparecer, rode: gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor && update-desktop-database ~/.local/share/applications && faça logout/login"
echo "Para desinstalar: rm -rf \"$PREFIX\" \"$WRAPPER\" \"$HOME/.local/share/applications/pdf-translate.desktop\" \"$HOME/.local/share/applications/${APP_ID}.desktop\" ~/.local/share/icons/hicolor/*/apps/pdf-translate.png"
