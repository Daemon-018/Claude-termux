# Claude Code + Ollama for Android/Termux

Run **real Claude Code** on Android/Termux using Ollama cloud models as the backend.

No API key needed. No Docker. Just install and code.

---

## What Is This?

This project lets you run the official [Claude Code](https://github.com/anthropics/claude-code) CLI on Android devices through Termux. It uses [Ollama](https://ollama.com) to access cloud-hosted AI models, so you get the full Claude Code experience without needing an Anthropic API key.

## Features

| Feature | Details |
|---------|---------|
| **Real Claude Code** | Official Anthropic CLI binary, compiled for ARM64 Android |
| **No API Key** | Models accessed through Ollama's cloud API |
| **4 Cloud Models** | Gemma 4 31B, Nemotron 3 Super, MiniMax M3, GLM 5.2 |
| **Full Tools** | Bash execution, file read/write/edit, grep, glob |
| **Interactive Mode** | Full terminal UI with conversation history |
| **Print Mode** | One-shot prompts for scripting |
| **Model Switching** | Switch models with `--model` flag |
| **Thinking Mode** | Extended reasoning available on supported models |

## Requirements

- Android 10+ with [Termux](https://termux.com) installed
- ARM64 (aarch64) device
- 2GB+ RAM
- Internet connection (for Ollama cloud models)

## Quick Start

```bash
# 1. Clone this repository
git clone https://github.com/yourusername/claude-termux.git
cd claude-termux

# 2. Run setup (installs everything)
bash setup.sh

# 3. Start Ollama
ollama serve &

# 4. Run Claude Code
claude
```

That's it. You're coding with Claude.

## Available Models

| Model | Provider | Context | Best For |
|-------|----------|---------|----------|
| `gemma4:31b-cloud` (default) | Google | 256K | General coding, vision tasks |
| `nemotron-3-super:cloud` | NVIDIA | 256K | Code generation, math |
| `minimax-m3:cloud` | MiniMax | 512K | Long context, complex tasks |
| `glm-5.2:cloud` | Zhipu AI | 1M | Deep reasoning, long documents |

### Switch Models

```bash
claude --model nemotron-3-super:cloud "Write a Python function"
claude --model glm-5.2:cloud "Analyze this codebase"
```

## Usage

### Interactive Mode

```bash
claude
```

Opens an interactive session with the default model (gemma4:31b-cloud).

### Print Mode (One-shot)

```bash
claude -p "Write a hello world in Python"
claude -p "Explain recursion" --model nemotron-3-super:cloud
```

### Interactive with Initial Prompt

```bash
claude "Help me debug this script"
```

### Multi-turn

```bash
claude "Create a Flask app" --max-turns 10
```

## Architecture

```
┌─────────────────────────────────────────────┐
│              Your Terminal                   │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│           claude (launcher)                  │
│   - Sets LD_PRELOAD for statx shim           │
│   - Routes to Ollama on localhost:11434       │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│        statx_pure.so (compatibility)         │
│   - Provides missing statx syscall           │
│   - Pure assembly, no dependencies           │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│         Claude Code (musl binary)            │
│   - Official Anthropic CLI                   │
│   - Runs on musl libc (Android/Termux)       │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│              Ollama (localhost)              │
│   - Serves cloud models locally              │
│   - No model weights stored on device        │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│         Cloud Model Providers                │
│   - Google, NVIDIA, MiniMax, Zhipu AI        │
└─────────────────────────────────────────────┘
```

## How It Works

### The Problem

Claude Code's official binary is compiled for x86_64 Linux with glibc. Android/Termux uses ARM64 with musl libc. The binary won't run because:

1. Wrong architecture (x86_64 vs ARM64)
2. Wrong libc (glibc vs musl)
3. Missing `statx` syscall in Termux's musl

### The Solution

1. **ARM64 build** - We use the `linux-arm64-musl` variant of Claude Code, compiled for ARM64 with musl libc.

2. **statx shim** - A tiny shared library provides the missing `statx` syscall (number 268 on ARM64). Loaded via `LD_PRELOAD`.

3. **Ollama backend** - Claude Code talks to Ollama on localhost. Ollama serves cloud models, so no local GPU needed.

## Setup Details

The `setup.sh` script:

1. Installs Ollama (if not present)
2. Installs Claude Code via npm
3. Compiles the statx compatibility shim
4. Creates the launcher at `/usr/bin/claude`
5. Pulls cloud models
6. Runs a verification test

## Manual Installation

If you prefer to set things up manually:

```bash
# Install Ollama
curl -fsSL https://ollama.com/install.sh | sh

# Install Claude Code
npm install -g @anthropic-ai/claude-code

# Create statx shim
cat > ~/statx_shim.c << 'EOF'
#include <sys/syscall.h>
#include <linux/stat.h>
struct statx_timestamp { long tv_sec; unsigned tv_nsec; long __reserved; };
struct statx { unsigned stx_mask; unsigned stx_blksize; unsigned long long stx_attributes;
    unsigned stx_nlink; unsigned stx_uid; unsigned stx_gid; unsigned short stx_mode;
    unsigned short __spare0[1]; unsigned long long stx_ino; unsigned long long stx_size;
    unsigned long long stx_blocks; unsigned long long stx_attributes_mask;
    struct statx_timestamp stx_atime, stx_btime, stx_ctime, stx_mtime;
    unsigned stx_rdev_major, stx_rdev_minor, stx_dev_major, stx_dev_minor;
    unsigned long long __spare2[14]; };
int statx(int d, const char *p, unsigned f, unsigned m, struct statx *b) {
    return syscall(268, d, p, f, m, b);
}
EOF
clang -shared -fPIC -o ~/statx_pure.so ~/statx_shim.c && rm ~/statx_shim.c

# Pull a model
ollama pull gemma4:31b-cloud

# Run
ollama serve &
claude -p "Hello!"
```

## Troubleshooting

### "claude: native binary not installed"
Run `npm install -g @anthropic-ai/claude-code`

### "cannot load statx_pure.so"
Recompile: `clang -shared -fPIC -o ~/statx_pure.so statx_shim.c`

### "model not found"
Pull the model: `ollama pull gemma4:31b-cloud`

### "address already in use"
Ollama is already running: `curl http://localhost:11434/api/tags`

### Claude Code exits immediately
Make sure Ollama is running: `ollama serve &`

### Slow first response
First call to a model may take 10-20 seconds as Ollama fetches metadata.

## Capabilities

### What Works
- Interactive coding sessions
- File creation and editing
- Bash command execution
- Code explanation and debugging
- Multi-turn conversations
- Vision tasks (on supported models)
- Extended thinking/reasoning

### What Doesn't Work
- Web search (requires Anthropic API key)
- Anthropic cloud models (requires API key)
- IDE integrations (VS Code extension)
- OAuth authentication

### Performance
- Response time: 2-10 seconds per turn (depends on model and internet)
- Context window: 256K-1M tokens depending on model
- No local storage used (models are cloud-streamed)

## Disclaimer

This project is an unofficial community effort. It is not affiliated with, endorsed by, or supported by Anthropic PBC or Ollama Inc.

Claude Code is copyrighted by Anthropic PBC. Ollama is copyrighted by Ollama Inc. This project merely provides packaging and compatibility layers to run these tools on Android/Termux.

Use of this software is subject to the licenses of:
- [Claude Code](https://github.com/anthropics/claude-code/blob/main/LICENSE)
- [Ollama](https://github.com/ollama/ollama/blob/main/LICENSE)

## License

MIT License - See [LICENSE](LICENSE) for details.

## Contributing

Pull requests welcome! Areas that need help:
- Testing on different Android devices
- Adding support for more models
- Improving error messages
- Documentation translations
