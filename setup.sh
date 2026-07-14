#!/bin/bash
# Claude Code + Ollama Setup for Android/Termux
# 
# This script sets up everything needed to run Claude Code on Android/Termux
# using Ollama cloud models as the backend.
#
# After setup, run:
#   ollama serve &
#   claude

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
  pkg install -y node
fi

if ! command -v gcc &> /dev/null; then
  info "Installing build tools..."
  pkg install -y clang make
fi

# Step 2: Install Claude Code
echo ""
echo "----------------------------------------------"
echo "Step 2: Installing Claude Code"
echo "----------------------------------------------"

if [ ! -f "/data/data/com.termux/files/usr/lib/node_modules/@anthropic-ai/claude-code-linux-arm64-musl/claude" ]; then
  info "Installing Claude Code (this takes 1-2 minutes)..."
  npm install -g @anthropic-ai/claude-code
else
  info "Claude Code already installed"
fi

# Step 3: Create statx compatibility shim
echo ""
echo "----------------------------------------------"
echo "Step 3: Creating statx compatibility shim"
echo "----------------------------------------------"

SHIM_SRC="/data/data/com.termux/files/home/statx_shim.c"
SHIM_OUT="/data/data/com.termux/files/home/statx_pure.so"

if [ ! -f "$SHIM_OUT" ]; then
  info "Compiling statx shim..."
  cat > "$SHIM_SRC" << 'CEOF'
/* statx compatibility shim for Android/Termux
 * The musl libc on Termux is missing the statx syscall (number 332)
 * which Claude Code requires. This shim provides it directly.
 */
#include <sys/syscall.h>
#include <unistd.h>
#include <fcntl.h>
#include <linux/stat.h>
#include <stdint.h>
#include <dirent.h>

struct statx_timestamp {
    int64_t tv_sec;
    uint32_t tv_nsec;
    int32_t __reserved;
};

struct statx {
    uint32_t stx_mask;
    uint32_t stx_blksize;
    uint64_t stx_attributes;
    uint32_t stx_nlink;
    uint32_t stx_uid;
    uint32_t stx_gid;
    uint16_t stx_mode;
    uint16_t __spare0[1];
    uint64_t stx_ino;
    uint64_t stx_size;
    uint64_t stx_blocks;
    uint64_t stx_attributes_mask;
    struct statx_timestamp stx_atime;
    struct statx_timestamp stx_btime;
    struct statx_timestamp stx_ctime;
    struct statx_timestamp stx_mtime;
    uint32_t stx_rdev_major;
    uint32_t stx_rdev_minor;
    uint32_t stx_dev_major;
    uint32_t stx_dev_minor;
    uint64_t __spare2[14];
};

int statx(int dirfd, const char *pathname, unsigned int flags, unsigned int mask, struct statx *buf) {
    return syscall(268, dirfd, pathname, flags, mask, buf);
}
CEOF
  clang -shared -fPIC -o "$SHIM_OUT" "$SHIM_SRC"
  rm -f "$SHIM_SRC"
  info "statx shim created: $SHIM_OUT"
else
  info "statx shim already exists"
fi

# Step 4: Create launcher
echo ""
echo "----------------------------------------------"
echo "Step 4: Creating launcher"
echo "----------------------------------------------"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/claude" /data/data/com.termux/files/usr/bin/claude
chmod +x /data/data/com.termux/files/usr/bin/claude
info "Launcher installed at /usr/bin/claude"

# Step 5: Pull models
echo ""
echo "----------------------------------------------"
echo "Step 5: Pulling Ollama models"
echo "----------------------------------------------"

# Start Ollama if not running
if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
  info "Starting Ollama..."
  nohup ollama serve > /tmp/ollama.log 2>&1 &
  sleep 5
fi

MODELS=("gemma4:31b-cloud" "nemotron-3-super:cloud" "minimax-m3:cloud" "glm-5.2:cloud")

for model in "${MODELS[@]}"; do
  if ! ollama list | grep -q "$model"; then
    info "Pulling $model..."
    ollama pull "$model" || warn "Failed to pull $model (will try later)"
  else
    info "$model already available"
  fi
done

# Step 6: Verify setup
echo ""
echo "----------------------------------------------"
echo "Step 6: Verification"
echo "----------------------------------------------"

info "Testing setup..."
if echo "test" | LD_PRELOAD="$SHIM_OUT" claude -p "reply ok" --model gemma4:31b-cloud --max-turns 1 > /tmp/test_out.txt 2>&1; then
  if grep -q -i "ok\|reply\|test\|hello\|hi" /tmp/test_out.txt; then
    info "Claude Code is working!"
  else
    warn "Claude Code ran but output was unexpected"
    cat /tmp/test_out.txt
  fi
else
  warn "Test failed - you may need to run 'ollama serve &' manually"
fi
rm -f /tmp/test_out.txt

# Summary
echo ""
echo "=============================================="
echo "  Setup Complete!"
echo "=============================================="
echo ""
echo "Quick start:"
echo "  ollama serve &"
echo "  claude"
echo ""
echo "Available models:"
echo "  gemma4:31b-cloud      (Google Gemma 4 31B)"
echo "  nemotron-3-super:cloud (NVIDIA Nemotron 3)"
echo "  minimax-m3:cloud      (MiniMax M3)"
echo "  glm-5.2:cloud         (Zhipu GLM 5.2)"
echo ""
echo "Switch models:"
echo "  claude --model nemotron-3-super:cloud "your prompt""
echo ""
echo "Documentation: ./README.md"
echo "=============================================="
