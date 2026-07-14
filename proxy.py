#!/usr/bin/env python3
"""
Claude Code ↔ Ollama Translation Proxy

Receives Anthropic Messages API format from Claude Code,
translates to Ollama's /api/chat format, and back.
Supports both streaming and non-streaming.
"""

import json
import http.server
import urllib.request
import urllib.parse
import sys
import uuid
import re

OLLAMA_HOST = "http://localhost:11434"
LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = 11440

def log(*args):
    print("[proxy]", *args, file=sys.stderr, flush=True)

# Default model mapping for Ollama
MODEL_MAP = {
    "claude-opus-4-8": "gemma4:31b-cloud",
    "claude-sonnet-4-8": "gemma4:31b-cloud",
    "claude-haiku-4-8": "gemma4:31b-cloud",
    "claude-fable-5": "gemma4:31b-cloud",
    "claude-3-opus": "gemma4:31b-cloud",
    "claude-3-sonnet": "gemma4:31b-cloud",
    "claude-3-haiku": "gemma4:31b-cloud",
    "claude-opus": "gemma4:31b-cloud",
    "claude-sonnet": "gemma4:31b-cloud",
    "claude-haiku": "gemma4:31b-cloud",
    "gpt-4": "gemma4:31b-cloud",
    "gpt-4o": "gemma4:31b-cloud",
    "default": "gemma4:31b-cloud",
}

def count_tokens(text):
    """Rough token count estimate."""
    return max(1, len(text) // 4)

def ollama_request(body, stream=False):
    """Send a request to Ollama and return the response."""
    body["stream"] = stream
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        f"{OLLAMA_HOST}/api/chat",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    try:
        return urllib.request.urlopen(req, timeout=300)
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8", errors="replace")
        log(f"Ollama HTTP error {e.code}: {error_body[:500]}")
        raise
    except Exception as e:
        log(f"Ollama connection error: {e}")
        raise

def count_input_tokens(anthropic_body):
    """Estimate input tokens from the request body."""
    total = 0
    # System prompt
    system = anthropic_body.get("system", "")
    if isinstance(system, str):
        total += count_tokens(system)
    elif isinstance(system, list):
        for s in system:
            if s.get("type") == "text":
                total += count_tokens(s.get("text", ""))
    # Messages
    for msg in anthropic_body.get("messages", []):
        content = msg.get("content", "")
        if isinstance(content, str):
            total += count_tokens(content)
        elif isinstance(content, list):
            for block in content:
                if block.get("type") == "text":
                    total += count_tokens(block.get("text", ""))
    # Role tokens (~4 per message)
    total += len(anthropic_body.get("messages", [])) * 4
    return max(1, total)

def anthropic_to_ollama(anthropic_body):
    """Convert Anthropic Messages API to Ollama /api/chat format.
    Strips tools/tool_choice since Ollama models don't need them."""
    raw_model = anthropic_body.get("model", "default")
    model = MODEL_MAP.get(raw_model, raw_model)
    max_tokens = anthropic_body.get("max_tokens", 4096)
    system_prompt = anthropic_body.get("system", "")

    ollama_messages = []

    # System prompt from field
    if system_prompt:
        if isinstance(system_prompt, list):
            for s in system_prompt:
                if s.get("type") == "text":
                    ollama_messages.append({"role": "system", "content": s.get("text", "")})
        elif isinstance(system_prompt, str):
            ollama_messages.append({"role": "system", "content": system_prompt})

    # Convert messages — skip tool_use blocks (history of tool calls)
    # but keep tool_result blocks as text
    for msg in anthropic_body.get("messages", []):
        role = msg["role"]
        content = msg.get("content", "")

        if role == "system":
            text = content if isinstance(content, str) else ""
            if not text and isinstance(content, list):
                text = " ".join(b.get("text", "") for b in content if b.get("type") == "text")
            ollama_messages.append({"role": "system", "content": text})
            continue

        if role == "assistant":
            # Assistant messages may have tool_use blocks — convert to text
            if isinstance(content, str):
                ollama_messages.append({"role": "assistant", "content": content})
            elif isinstance(content, list):
                texts = []
                for block in content:
                    btype = block.get("type")
                    if btype == "text":
                        texts.append(block.get("text", ""))
                    elif btype == "tool_use":
                        # Convert tool_use to descriptive text
                        name = block.get("name", "tool")
                        inp = json.dumps(block.get("input", {}))
                        texts.append(f"[Using {name}: {inp}]")
                ollama_messages.append({"role": "assistant", "content": "\n".join(texts)})
            continue

        if role == "user":
            if isinstance(content, str):
                ollama_messages.append({"role": "user", "content": content})
            elif isinstance(content, list):
                texts = []
                for block in content:
                    btype = block.get("type")
                    if btype == "text":
                        texts.append(block.get("text", ""))
                    elif btype == "tool_result":
                        tc = block.get("content", "")
                        tool_id = block.get("tool_use_id", "")
                        if isinstance(tc, list):
                            for t in tc:
                                if t.get("type") == "text":
                                    texts.append(f"[Tool {tool_id} result: {t.get('text', '')}]")
                        elif isinstance(tc, str):
                            texts.append(f"[Tool {tool_id} result: {tc}]")
                    elif btype == "image":
                        texts.append("[Image]")
                ollama_messages.append({"role": "user", "content": "\n".join(texts)})

    options = {"num_predict": max_tokens}
    if "temperature" in anthropic_body:
        options["temperature"] = anthropic_body["temperature"]

    return {
        "model": model,
        "messages": ollama_messages,
        "options": options
    }

def make_anthropic_response(content_text, model):
    """Build a non-streaming Anthropic response from text."""
    out_tokens = count_tokens(content_text)
    return {
        "id": f"msg_{uuid.uuid4().hex[:24]}",
        "type": "message",
        "role": "assistant",
        "content": [{"type": "text", "text": content_text}],
        "model": model,
        "stop_reason": "end_turn",
        "stop_sequence": None,
        "usage": {"input_tokens": 10, "output_tokens": out_tokens}
    }

class ProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"status": "running", "proxy": "claude-termux"}).encode())

    def do_POST(self):
        body_bytes = self.rfile.read(int(self.headers.get("Content-Length", 0)))

        try:
            anthropic_body = json.loads(body_bytes)
        except json.JSONDecodeError as e:
            self._error(400, "invalid_json", str(e))
            return

        path = self.path.split("?")[0]

        if path == "/v1/messages":
            self._handle_messages(anthropic_body)
        else:
            self._error(404, "not_found", f"Unknown: {path}")

    def _handle_messages(self, anthropic_body):
        raw_model = anthropic_body.get("model", "unknown")
        mapped_model = MODEL_MAP.get(raw_model, raw_model)
        stream = anthropic_body.get("stream", False)
        has_tools = len(anthropic_body.get("tools", []))
        log(f"Request: {raw_model} -> {mapped_model} | stream={stream} | msgs={len(anthropic_body.get('messages',[]))} | tools={has_tools}")

        # Log last user message
        msgs = anthropic_body.get("messages", [])
        if msgs:
            last = msgs[-1].get("content", "")
            if isinstance(last, str):
                log(f"  Last msg: {last[:100]}")
            elif isinstance(last, list):
                for b in last:
                    if b.get("type") == "text":
                        log(f"  Last msg: {b.get('text','')[:100]}")
                        break

        # STRIP tools and tool_choice — Ollama models don't need them
        # and they confuse the model into producing bad tool_use responses
        anthropic_body.pop("tools", None)
        anthropic_body.pop("tool_choice", None)

        try:
            ollama_body = anthropic_to_ollama(anthropic_body)

            if stream:
                self._handle_streaming(ollama_body, raw_model)
            else:
                self._handle_non_streaming(ollama_body, raw_model)

        except urllib.error.HTTPError as e:
            self._error(e.code, "upstream_error", f"Ollama error {e.code}")
        except Exception as e:
            log(f"Error: {e}")
            self._error(500, "proxy_error", str(e))

    def _handle_non_streaming(self, ollama_body, model):
        resp = ollama_request(ollama_body, stream=False)
        ollama_response = json.loads(resp.read())
        content = ollama_response.get("message", {}).get("content", "")

        # If tool context detected, return empty end_turn
        has_tool_context = any(
            msg["role"] == "system" and "system-reminder" in msg.get("content", "")
            for msg in ollama_body.get("messages", [])
        )
        if has_tool_context:
            content = ""

        response = make_anthropic_response(content, model)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("x-request-id", uuid.uuid4().hex[:16])
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(json.dumps(response).encode())
        log(f"  Non-streaming response sent ({len(content)} chars, tool_context={has_tool_context})")

    def _handle_streaming(self, ollama_body, model):
        """Handle streaming: get full response from Ollama, send as SSE.
        When the request had tools (stripped earlier), return empty content
        to signal the model declined tool usage."""
        # Detect if this was a request that originally had tools
        # by checking if the system prompt contains "system-reminder"
        has_tool_context = False
        for msg in ollama_body.get("messages", []):
            if msg["role"] == "system" and "system-reminder" in msg.get("content", ""):
                has_tool_context = True
                break

        resp = ollama_request(ollama_body, stream=True)

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.send_header("x-request-id", uuid.uuid4().hex[:16])
        self.end_headers()

        message_id = f"msg_{uuid.uuid4().hex[:24]}"

        # Count total messages for input token estimate
        total_msg_text = ""
        for m in ollama_body.get("messages", []):
            c = m.get("content", "")
            total_msg_text += c if isinstance(c, str) else str(c)
        in_tokens = count_tokens(total_msg_text) + 4

        # message_start
        self._sse("message_start", {
            "type": "message_start",
            "message": {
                "id": message_id, "type": "message", "role": "assistant",
                "content": [], "model": model,
                "stop_reason": None, "stop_sequence": None,
                "usage": {"input_tokens": in_tokens, "output_tokens": 0}
            }
        })

        # content_block_start
        self._sse("content_block_start", {
            "type": "content_block_start", "index": 0,
            "content_block": {"type": "text", "text": ""}
        })

        if has_tool_context:
            # When tools were present, skip model output and send end_turn immediately
            # This prevents Claude Code's retry loop (it loops waiting for tool_use)
            full_text = ""
            self._sse("content_block_delta", {
                "type": "content_block_delta", "index": 0,
                "delta": {"type": "text_delta", "text": ""}
            })
        else:
            full_text = ""
            for line in resp:
                line = line.decode("utf-8", errors="replace").strip()
                if not line:
                    continue
                try:
                    chunk = json.loads(line)
                    content = chunk.get("message", {}).get("content", "")
                    if content:
                        full_text += content
                        self._sse("content_block_delta", {
                            "type": "content_block_delta", "index": 0,
                            "delta": {"type": "text_delta", "text": content}
                        })
                    if chunk.get("done"):
                        break
                except json.JSONDecodeError:
                    continue

        out_tokens = count_tokens(full_text)
        self._sse("content_block_stop", {"type": "content_block_stop", "index": 0})
        self._sse("message_delta", {
            "type": "message_delta",
            "delta": {"stop_reason": "end_turn", "stop_sequence": None},
            "usage": {"output_tokens": out_tokens}
        })
        self._sse("message_stop", {"type": "message_stop"})

        log(f"  Streaming response sent ({len(full_text)} chars, tool_context={has_tool_context})")

    def _sse(self, event_type, data):
        """Send an SSE event with proper format."""
        try:
            self.wfile.write(f"event: {event_type}\ndata: {json.dumps(data)}\n\n".encode())
            self.wfile.flush()
        except:
            pass

    def _error(self, code, etype, msg):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({
            "type": "error",
            "error": {"type": etype, "message": msg}
        }).encode())

    def log_message(self, *a): pass

def main():
    log(f"Starting proxy on {LISTEN_HOST}:{LISTEN_PORT}")
    log(f"Ollama backend: {OLLAMA_HOST}")
    try:
        http.server.HTTPServer((LISTEN_HOST, LISTEN_PORT), ProxyHandler).serve_forever()
    except KeyboardInterrupt:
        log("Shutdown")

if __name__ == "__main__":
    main()
