#!/bin/bash
# Claude Code + Ollama Setup for Android/Termux
#
# This script sets up everything needed to run Claude Code on Android/Termux
# using Ollama cloud models as the backend via the translation proxy.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo "=============================================="
echo "  Claude Code + Ollama Setup for Android/Termux"
echo "=============================================="
echo ""

# Check platform
if [ ! -d "/data/data/com.termux" ]; then
  error "This script only works on Android/Termux"
fi

ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ]; then
  error "Unsupported architecture: $ARCH (need aarch64)"
fi

info "Platform: Android/Termux ($ARCH)"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Step 1: Install dependencies
echo ""
echo "----------------------------------------------"
echo "Step 1: Installing dependencies"
echo "----------------------------------------------"

if ! command -v ollama &> /dev/null; then
  info "Installing Ollama..."
  curl -fsSL https://ollama.com/install.sh | sh
else
  info "Ollama already installed: $(ollama --version 2>/dev/null || echo 'unknown')"
fi

if ! command -v node &> /dev/null; then
  info "Installing Node.js..."
  pkg install -y nodejs
fi

if ! command -v python3 &> /dev/null; then
  info "Installing Python 3..."
  pkg install -y python
fi

# Step 2: Install Claude Code binary
echo ""
echo "----------------------------------------------"
echo "Step 2: Installing Claude Code binary"
echo "----------------------------------------------"

if [ ! -f "$SCRIPT_DIR/bin/claude" ]; then
  info "Downloading Claude Code (musl ARM64)..."
  cd "$SCRIPT_DIR"
  mkdir -p bin
  # Download from npm registry
  VERSION=$(npm view @anthropic-ai/claude-code version 2>/dev/null || echo "2.1.209")
  TARBALL_URL=$(npm view @anthropic-ai/claude-code dist.tarball 2>/dev/null || echo "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-2.1.209.tgz")
  curl -sL "$TARBALL_URL" -o /tmp/claude.tgz
  tar xzf /tmp/claude.tgz -C /tmp/
  # Find binary inside tarball
  find /tmp/package -name "claude" -type f | head -1 | while read f; do
    cp "$f" "$SCRIPT_DIR/bin/claude"
    chmod +x "$SCRIPT_DIR/bin/claude"
  done
  rm -rf /tmp/package /tmp/claude.tgz
  info "Claude Code binary installed"
fi

# Step 3: Setup musl libc runtime
echo ""
echo "----------------------------------------------"
echo "Step 3: Setting up musl libc runtime"
echo "----------------------------------------------"

if [ ! -d "$SCRIPT_DIR/musl-libc" ]; then
  info "Setting up musl libc..."
  cd "$SCRIPT_DIR"
  mkdir -p musl-libc

  # Download musl libc for ARM64
  curl -sL "https://musl.cc/aarch64-linux-musl-cross.tgz" -o /tmp/musl.tgz
  tar xzf /tmp/musl.tgz -C /tmp/
  cp /tmp/aarch64-linux-musl-cross/lib/libc.so musl-libc/
  ln -sf libc.so musl-libc/ld-musl-aarch64.so.1
  ln -sf libc.so musl-libc/libc.musl-aarch64.so.1
  rm -rf /tmp/aarch64-linux-musl-cross /tmp/musl.tgz
  info "musl libc ready"
fi

# Step 4: Compile statx shim
echo ""
echo "----------------------------------------------"
echo "Step 4: Compiling statx shim"
echo "----------------------------------------------"

if [ ! -f "$SCRIPT_DIR/statx_pure.so" ]; then
  info "Compiling statx compatibility shim..."
  gcc -shared -fPIC -o "$SCRIPT_DIR/statx_pure.so" "$SCRIPT_DIR/statx_shim.c" 2>/dev/null || \
  clang -shared -fPIC -o "$SCRIPT_DIR/statx_pure.so" "$SCRIPT_DIR/statx_shim.c" 2>/dev/null || \
  aarch64-linux-musl-gcc -shared -fPIC -o "$SCRIPT_DIR/statx_pure.so" "$SCRIPT_DIR/statx_shim.c"
  info "statx shim compiled"
fi

# Step 5: Install launcher
echo ""
echo "----------------------------------------------"
echo "Step 5: Installing launcher"
echo "----------------------------------------------"

cp "$SCRIPT_DIR/claude" /data/data/com.termux/files/usr/bin/claude
chmod +x /data/data/com.termux/files/usr/bin/claude
info "Launcher installed at /usr/bin/claude"

# Step 6: Pull Ollama models
echo ""
echo "----------------------------------------------"
echo "Step 6: Pulling Ollama models"
echo "----------------------------------------------"

# Start Ollama if not running
if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
  info "Starting Ollama..."
  nohup ollama serve > /tmp/ollama.log 2>&1 &
  sleep 5
fi

# Read models from models.json
if [ -f "$SCRIPT_DIR/models/models.json" ]; then
  MODELS=$(grep -o '"model": *"[^"]*"' "$SCRIPT_DIR/models/models.json" | cut -d'"' -f4)
  for model in $MODELS; do
    if ! ollama list | grep -q "$model"; then
      info "Pulling $model..."
      ollama pull "$model" || warn "Failed to pull $model"
    else
      info "$model already available"
    fi
  done
fi

# Step 7: Verify
echo ""
echo "----------------------------------------------"
echo "Step 7: Verification"
echo "----------------------------------------------"

info "Testing setup..."
if result=$(claude -p "reply OK in one word" 2>/dev/null); then
  echo "$result"
  info "Claude Code is working!"
else
  warn "Test failed - make sure ollama serve & is running"
fi

echo ""
echo "=============================================="
echo "  Setup Complete!"
echo "=============================================="
echo ""
echo "Quick start:"
echo "  ollama serve &"
echo "  claude"
echo ""
echo "One-shot:"
echo "  claude -p \"Write a Python script\""
echo ""
echo "Switch model:"
echo "  claude --model llama3.3-70b-cloud -p \"explain recursion\""
echo ""
