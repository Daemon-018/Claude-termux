#!/bin/bash
# Claude-termux Installer
# One-line: curl -fsSL https://raw.githubusercontent.com/Daemon-018/Claude-termux/main/install.sh | bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo "=============================================="
echo "  Claude Code + Ollama for Android/Termux"
echo "=============================================="
echo ""

# --- Platform check ---
[ -d "/data/data/com.termux" ] || error "This installer only works on Android/Termux"
[ "$(uname -m)" = "aarch64" ] || error "Unsupported architecture: $(uname -m) (need aarch64)"
info "Platform: Android/Termux aarch64 ✅"

# --- Clone repo ---
REPO="https://github.com/Daemon-018/Claude-termux.git"
DEST="${HOME}/claude-termux"

if [ -d "$DEST" ]; then
  info "Updating existing installation at $DEST"
  cd "$DEST" && git pull --ff-only 2>/dev/null || warn "Could not git pull, will re-use existing files"
else
  info "Downloading Claude-termux..."
  command -v git >/dev/null 2>&1 || pkg install -y git 2>/dev/null || error "Install git: pkg install git"
  git clone --depth=1 "$REPO" "$DEST" || error "Failed to clone repo"
fi

cd "$DEST"

# --- Install system dependencies ---
info "Installing dependencies..."
pkg install -y python nodejs clang ollama 2>/dev/null || {
  pkg update -y 2>/dev/null
  pkg install -y python nodejs clang 2>/dev/null
  # Ollama install if not present
  command -v ollama >/dev/null 2>&1 || curl -fsSL https://ollama.com/install.sh | sh
}

# --- Download Claude Code binary (musl ARM64) ---
if [ ! -f "bin/claude" ]; then
  info "Downloading Claude Code binary (~250MB)..."
  mkdir -p bin
  VERSION=$(npm view @anthropic-ai/claude-code version 2>/dev/null || echo "2.1.209")
  TARBALL="https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${VERSION}.tgz"
  curl -fsL "$TARBALL" -o /tmp/claude.tgz
  tar xzf /tmp/claude.tgz -C /tmp/
  find /tmp/package -name "claude" -type f | head -1 | while read f; do
    cp "$f" bin/claude && chmod +x bin/claude
  done
  rm -rf /tmp/package /tmp/claude.tgz
  info "Claude Code binary ready"
fi

# --- Setup musl libc ---
if [ ! -d "musl-libc" ]; then
  info "Setting up musl libc..."
  mkdir -p musl-libc
  curl -fsL "https://musl.cc/aarch64-linux-musl-cross.tgz" -o /tmp/musl.tgz
  tar xzf /tmp/musl.tgz -C /tmp/
  cp /tmp/aarch64-linux-musl-cross/lib/libc.so musl-libc/
  ln -sf libc.so musl-libc/ld-musl-aarch64.so.1
  ln -sf libc.so musl-libc/libc.musl-aarch64.so.1
  rm -rf /tmp/aarch64-linux-musl-cross /tmp/musl.tgz
  info "musl libc ready"
fi

# --- Compile statx shim ---
if [ ! -f "statx_pure.so" ] && [ -f "statx_shim.c" ]; then
  info "Compiling statx shim..."
  clang -shared -fPIC -o statx_pure.so statx_shim.c 2>/dev/null || \
    gcc -shared -fPIC -o statx_pure.so statx_shim.c 2>/dev/null || \
    warn "statx shim compilation failed (may not be needed on newer Android)"
fi

# --- Install launcher symlink ---
info "Installing claude command..."
ln -sf "$DEST/claude" /data/data/com.termux/files/usr/bin/claude
info "Type 'claude' from anywhere ✅"

# --- Start Ollama ---
if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
  info "Starting Ollama..."
  nohup ollama serve > /tmp/ollama.log 2>&1 &
  sleep 3
fi

# --- Pull default model ---
DEFAULT_MODEL="gemma4:31b-cloud"
if command -v ollama >/dev/null 2>&1; then
  if ! ollama list 2>/dev/null | grep -q "$DEFAULT_MODEL"; then
    info "Pulling default model ($DEFAULT_MODEL)..."
    ollama pull "$DEFAULT_MODEL" 2>/dev/null || warn "Model pull failed (skip with --no-pull)"
  fi
fi

# --- Test ---
echo ""
echo "----------------------------------------------"
echo "  Verification"
echo "----------------------------------------------"
if result=$(claude -p "reply OK" 2>/dev/null); then
  echo "  $result"
  info "Claude Code is working! 🎉"
else
  warn "Test failed — run 'ollama serve &' then try again"
fi

echo ""
echo "=============================================="
echo "  Install Complete!"
echo "=============================================="
echo ""
echo "  Usage:"
echo "    claude                           # Interactive"
echo "    claude -p \"Write a script\"      # One-shot"
echo "    claude --model llama3.3-70b-cloud -p \"...\""
echo ""
echo "  First time? Run:  ollama serve &"
echo ""
