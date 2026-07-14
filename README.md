# Claude Code + Ollama for Android/Termux

Run **real Claude Code** on Android/Termux using Ollama cloud models as the backend.

No API key needed. No Docker. Just install and code.

---

## What Is This?

This project lets you run the official [Claude Code](https://github.com/anthropics/claude-code) CLI on Android devices through Termux. It uses [Ollama](https://ollama.com) to access cloud-hosted AI models, so you get the full Claude Code experience without needing an Anthropic API key.

**How it works:**
1. The official Claude Code binary (v2.1.209, musl ARM64) runs on Termux
2. A local translation proxy (Python) intercepts Claude Code's Anthropic-format API requests
3. The proxy translates them to Ollama's `/api/chat` format and routes them to your local Ollama server
4. Responses are translated back to Anthropic's Messages API format

## Features

| Feature | Details |
|---------|---------|
| **Real Claude Code** | Official Anthropic CLI binary, compiled for ARM64 Android |
| **No API Key** | Models accessed through Ollama's cloud API |
| **4 Cloud Models** | Gemma 4 31B, Gemma 4 8B, Llama 3.3 70B, Qwen 3 235B |
| **Translation Proxy** | Python proxy converts Anthropic API ↔ Ollama API |
| **Interactive Mode** | Full terminal UI with conversation history |
| **Print Mode** | One-shot prompts for scripting |
| **Model Switching** | Switch models with `--model` flag |

## Requirements

- Android 10+ with [Termux](https://termux.com) installed
- ARM64 (aarch64) device
- 2GB+ RAM
- Internet connection (for Ollama cloud models)
- Python 3.x (Termux package)

## Quick Start

```bash
# 1. Clone this repository
git clone https://github.com/Daemon-018/Claude-termux.git
cd Claude-termux

# 2. Run setup (installs everything: Ollama, Node.js, musl, etc.)
bash setup.sh

# 3. Start Ollama
ollama serve &

# 4. Run Claude Code (auto-starts the translation proxy)
./claude
```

That's it. You're coding with Claude.

## Available Models

| Model | Provider | Best For |
|-------|----------|----------|
| `gemma4:31b-cloud` (default) | Google | General coding, vision tasks |
| `gemma4:8b-cloud` | Google | Fast responses, simple tasks |
| `llama3.3-70b-cloud` | Meta | Code generation, math |
| `qwen3-235b-cloud` | Alibaba | Deep reasoning, long context |

### Switch Models

```bash
./claude --model llama3.3-70b-cloud "Write a Python function"
./claude --model qwen3-235b-cloud "Analyze this codebase"
```

## Usage

### Print Mode (One-shot)
```bash
./claude -p "Write a hello world in Python"
./claude -p "Explain recursion" --model llama3.3-70b-cloud
```

### Interactive Mode
```bash
./claude
```

### Interactive with Initial Prompt
```bash
./claude "Help me debug this script"
```

## Architecture

```
┌───────────────────────────────────────────────────────────────┐
│  Android/Termux Device                                         │
│                                                                │
│  ┌─────────────────────┐         ┌──────────────────────┐    │
│  │    Claude Code CLI   │ ──────▶ │   Translation Proxy   │    │
│  │  (musl ARM64 binary) │  HTTP   │   (Python, port 11440) │    │
│  │  Sends Anthropic API │         │   Converts formats     │    │
│  └─────────────────────┘         └──────────┬───────────┘    │
│                                              │ HTTP           │
│                                      ┌───────▼────────┐      │
│                                      │   Ollama Server  │      │
│                                      │  (localhost:11434)│      │
│                                      └────────┬────────┘      │
└───────────────────────────────────────────────┼───────────────┘
                                                │
                                        ┌───────▼────────┐
                                        │  Cloud Models    │
                                        │  gemma4:31b     │
                                        │  llama3.3-70b   │
                                        │  qwen3-235b     │
                                        └────────────────┘
```

### What the proxy does

The translation proxy handles format conversion between two incompatible APIs:

- **Incoming (from Claude Code):** Anthropic Messages API format with `messages[]`, `tools[]`, `system[]`
- **Outgoing (to Ollama):** Ollama `/api/chat` format with `messages[]` and `options`
- **Response:** Ollama streaming chunks → Anthropic SSE events (`message_start`, `content_block_delta`, `message_stop`)

The proxy also:
- Maps Claude model names (e.g., `claude-opus-4-8`) to Ollama model names
- Strips tool definitions (Ollama models don't use them in the same way)
- Adds proper SSE event types and token counts for Claude Code compatibility

## Troubleshooting

### "Ollama not running"
Make sure Ollama is running:
```bash
ollama --version
ollama serve &
```

### "Port already in use"
The proxy may need to be restarted:
```bash
pkill -f proxy.py
./claude
```

### "Model not found"
Pull the model first:
```bash
ollama pull gemma4:31b
```

### "Claude Code not found"
Make sure you have Node.js installed (required for Claude Code):
```bash
node --version  # Should be v18+
```

### Proxy keeps looping
If Claude Code hangs in a loop, restart everything:
```bash
pkill -f proxy.py
pkill -f ollama
ollama serve &
./claude
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request
