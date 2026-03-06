# nanobot Architecture

> Ultra-lightweight personal AI assistant (~4,000 lines of core Python + TypeScript WhatsApp bridge)

## Overview

nanobot is a multi-channel, multi-provider AI assistant framework. It connects to chat platforms (Telegram, Discord, WhatsApp, Slack, etc.), routes messages through an async bus to a central agent loop, calls LLM providers with tool-use capabilities, and sends responses back.

```
┌─────────────────────────────────────────────────────────────┐
│                        User                                 │
│   Telegram │ Discord │ WhatsApp │ Slack │ Email │ CLI │ ... │
└──────┬─────┴────┬────┴────┬─────┴───┬───┴───┬───┴──┬──┘
       │          │         │         │       │      │
       ▼          ▼         ▼         ▼       ▼      ▼
┌─────────────────────────────────────────────────────────────┐
│                    Channel Layer                            │
│  BaseChannel implementations (one per platform)             │
│  - Permission checks (allow_from)                           │
│  - Platform-specific message parsing                        │
│  - Media handling (images, voice, documents)                │
└──────────────────────┬──────────────────────────────────────┘
                       │ InboundMessage
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                    MessageBus                               │
│  Two async queues:                                          │
│  - inbound:  Channel → Agent                                │
│  - outbound: Agent → Channel                                │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                    AgentLoop                                │
│  1. Consume message from bus                                │
│  2. Build context (system prompt + history + memory)        │
│  3. Call LLM with tools                                     │
│  4. Execute tool calls (iterative loop, max 40 iterations)  │
│  5. Consolidate memory if window exceeded                   │
│  6. Publish response to bus                                 │
└────┬──────────┬──────────┬──────────┬───────────────────────┘
     │          │          │          │
     ▼          ▼          ▼          ▼
  LLM Provider  Tools   Memory    Sessions
```

---

## Entry Points

nanobot has two main execution modes, both driven by the Typer CLI (`nanobot/cli/commands.py`):

| Command | What it does |
|---|---|
| `nanobot agent` | Interactive CLI chat (or single-shot with `-m "message"`) |
| `nanobot gateway` | Multi-channel server: starts all enabled channels, cron, heartbeat |
| `nanobot onboard` | First-time setup: creates `~/.nanobot/config.json` and workspace |
| `nanobot status` | Shows config, provider keys, workspace status |
| `nanobot channels status` | Shows which channels are enabled |
| `nanobot channels login` | Links WhatsApp via QR code (starts the Node.js bridge) |
| `nanobot provider login <name>` | OAuth login for providers like OpenAI Codex |

### How `nanobot agent` works

```python
# Single message mode
nanobot agent -m "What's the weather?"
# → Creates AgentLoop, calls process_direct(), prints response, exits

# Interactive mode
nanobot agent
# → Creates AgentLoop, starts bus consumer loop
# → Uses prompt_toolkit for input (history, paste support)
# → Publishes InboundMessage to bus → AgentLoop processes → OutboundMessage consumed and printed
```

### How `nanobot gateway` works

```python
# Starts everything concurrently:
asyncio.gather(
    agent.run(),           # AgentLoop consuming from bus
    channels.start_all(),  # All enabled channels listening
)
# Plus: CronService.start(), HeartbeatService.start()
```

---

## Core Components

### 1. MessageBus (`nanobot/bus/`)

The decoupling layer between channels and the agent. Two `asyncio.Queue`s:

- `inbound`: Channels push `InboundMessage` (channel, sender_id, chat_id, content, media, metadata)
- `outbound`: Agent pushes `OutboundMessage` (channel, chat_id, content, reply_to, media)

The `ChannelManager` dispatches outbound messages to the correct channel based on `msg.channel`.

### 2. Channel System (`nanobot/channels/`)

Each channel extends `BaseChannel` with `start()`, `stop()`, `send()`:

| Channel | Transport | Notes |
|---|---|---|
| Telegram | python-telegram-bot | Proxy support, voice transcription via Groq |
| Discord | Raw WebSocket gateway | Message content intent, thread support |
| WhatsApp | WebSocket to Node.js bridge | Baileys library, QR auth |
| Feishu/Lark | WebSocket long connection | App ID/secret, emoji reactions |
| Slack | Socket Mode SDK | No public IP needed, thread replies |
| DingTalk | Stream mode | Staff ID allowlist |
| Email | IMAP polling + SMTP | Auto-reply, configurable poll interval |
| Matrix | matrix-nio with E2EE | Encrypted rooms, media handling |
| QQ | botpy SDK | Sandbox testing support |
| Mochat | Socket.IO | Mention-based reply delay |

Permission model: each channel has an `allow_from` list. Empty = deny all, `["*"]` = allow all.

### 3. AgentLoop (`nanobot/agent/loop.py`)

The core processing engine. For each inbound message:

```
1. Get/create session (keyed by channel:chat_id)
2. Handle special commands (/new, /stop, /help)
3. Initialize MCP servers (lazy, first message only)
4. Build context via ContextBuilder
5. LLM call loop (up to max_iterations=40):
   a. Call provider.chat(messages, tools, model, ...)
   b. If response has tool_calls → execute each via ToolRegistry
   c. Append tool results to messages
   d. Repeat until no more tool calls or max iterations
6. Save turn to session (append-only JSONL)
7. Consolidate memory if unconsolidated messages ≥ memory_window
8. Publish OutboundMessage to bus
```

### 4. ContextBuilder (`nanobot/agent/context.py`)

Assembles the system prompt from multiple sources:

```
Identity (runtime info, workspace path, guidelines)
  + Bootstrap files (AGENTS.md, SOUL.md, USER.md, TOOLS.md, IDENTITY.md)
  + Long-term memory (MEMORY.md)
  + Always-on skills
  + Skills summary (for progressive loading)
```

Also builds user messages with runtime context (current time, channel, chat_id) and handles multimodal content (base64-encoded images).

### 5. Memory System (`nanobot/agent/memory.py`)

Two-layer persistent memory:

- `MEMORY.md` — Long-term facts (updated by LLM via `save_memory` tool call)
- `HISTORY.md` — Grep-searchable timestamped log

Consolidation is triggered when unconsolidated messages exceed `memory_window` (default 100). The LLM summarizes old messages into a history entry and updates long-term memory. Messages themselves are append-only (never deleted) for LLM cache efficiency.

### 6. Session Management (`nanobot/session/manager.py`)

- Sessions stored as JSONL files (one message per line)
- Key format: `channel:chat_id` (e.g., `telegram:12345`)
- Tracks `last_consolidated` index for memory consolidation offset
- `get_history()` returns unconsolidated messages, aligned to start at a user turn

### 7. Provider System (`nanobot/providers/`)

**Registry** (`registry.py`): A tuple of `ProviderSpec` dataclasses defining all supported providers. Each spec includes:
- Keywords for model matching (e.g., "claude" → Anthropic)
- LiteLLM prefix for model routing
- Gateway detection (by API key prefix or base URL substring)
- Per-model parameter overrides

**Provider matching priority:**
1. Forced provider (explicit in config)
2. Explicit prefix in model name (`anthropic/claude-opus`)
3. Keyword matching
4. Gateway detection
5. Fallback to first available with API key

**Provider types:**
- Standard: Anthropic, OpenAI, DeepSeek, Gemini, Groq, Zhipu, Qwen, Moonshot, MiniMax
- Gateways: OpenRouter, AiHubMix, SiliconFlow, VolcEngine (route any model)
- Local: vLLM, Ollama-compatible
- Direct: Custom OpenAI-compatible endpoints (bypass LiteLLM)
- OAuth: OpenAI Codex, GitHub Copilot

**Base interface** (`base.py`):
```python
class LLMProvider(ABC):
    async def chat(messages, tools, model, max_tokens, temperature, reasoning_effort) -> LLMResponse
    def get_default_model() -> str
```

`LLMResponse` contains: content, tool_calls, finish_reason, usage, reasoning_content, thinking_blocks.

### 8. Tool System (`nanobot/agent/tools/`)

Tools extend `Tool` ABC with `name`, `description`, `parameters` (JSON Schema), and `execute()`.

| Tool | What it does |
|---|---|
| `read_file` | Read file contents (with workspace restriction option) |
| `write_file` | Write/create files |
| `edit_file` | Surgical edits (old_string → new_string) |
| `list_dir` | List directory contents |
| `exec` | Shell command execution (timeout, dangerous command blocking) |
| `web_search` | Brave Search API |
| `web_fetch` | HTTP fetch with readability extraction |
| `message` | Send to a specific channel/chat (bypasses normal response flow) |
| `spawn` | Launch background subagents |
| `cron` | Schedule tasks (at/every/cron expressions) |
| `mcp_*` | Dynamic tools from MCP servers |

**ToolRegistry**: Central registry with `register()`, `get_definitions()` (for LLM), `execute()`.

**MCP Integration** (`mcp.py`): Lazy-loaded on first message. Supports stdio (local) and HTTP (remote) transports. Each MCP tool is wrapped as a native nanobot `Tool` with name prefix `mcp_{server}_{tool}`.

### 9. Subagent System (`nanobot/agent/subagent.py`)

Background task execution via the `spawn` tool:

- Each subagent gets a focused system prompt, limited tools (no message/spawn/cron), max 15 iterations
- Results announced back to main agent via system message
- Cancellable per session (`/stop` command)
- Tracked by session key for cleanup

### 10. Skills System (`nanobot/agent/skills.py`)

Skills are markdown files (`SKILL.md`) that teach the agent how to use specific tools:

- Loaded from workspace (`skills/`) and builtin (`nanobot/skills/`)
- YAML frontmatter for metadata (description, requirements, always flag)
- Requirements checking: CLI binaries, environment variables
- Progressive loading: summary in system prompt, full content loaded on-demand via `read_file`
- Built-in skills: clawhub, cron, github, memory, skill-creator, summarize, tmux, weather

### 11. Cron Service (`nanobot/cron/service.py`)

Scheduled task execution:

- Schedule types: `at` (one-shot timestamp), `every` (interval ms), `cron` (cron expression with timezone)
- Persistent storage in `jobs.json`
- Auto-reloads on external file modification
- Callback-based: when a job fires, it calls `on_job` which routes through `AgentLoop.process_direct()`
- Job results can be delivered to a specific channel/chat

### 12. Heartbeat Service (`nanobot/heartbeat/service.py`)

Periodic agent wake-up (default every 30 minutes):

1. **Decision phase**: Reads `HEARTBEAT.md`, asks LLM via virtual tool call whether there are active tasks
2. **Execution phase**: If LLM returns `run`, executes tasks through the full agent loop
3. **Delivery**: Results sent to the most recently active channel

---

## WhatsApp Bridge (`bridge/`)

A separate Node.js/TypeScript component using the Baileys library (WhatsApp Web reverse engineering):

```
WhatsApp Web ←→ Baileys ←→ BridgeServer (WebSocket on localhost:3001) ←→ Python WhatsAppChannel
```

- Security: localhost-only binding, optional `BRIDGE_TOKEN` authentication
- Handles QR code generation, message forwarding (text, images, video, documents, voice), reconnection
- Built separately (`npm install && npm run build`), auto-setup on first `nanobot channels login`

---

## Configuration

Config file: `~/.nanobot/config.json` (Pydantic-validated, supports both camelCase and snake_case)

```
Config
├── agents.defaults (model, provider, temperature, max_tokens, memory_window, reasoning_effort)
├── channels (per-channel: enabled, tokens, allow_from, etc.)
├── providers (per-provider: api_key, api_base, extra_headers)
├── gateway (host, port, heartbeat interval)
└── tools (web search key, exec timeout, restrict_to_workspace, mcp_servers)
```

Workspace: `~/.nanobot/workspace/` (sessions, memory, skills, templates)

---

## Docker Deployment

```yaml
# docker-compose.yml
services:
  nanobot-gateway:
    build: .
    command: ["gateway"]
    ports: ["18790:18790"]
    volumes: ["~/.nanobot:/root/.nanobot"]
```

Base image: `ghcr.io/astral-sh/uv:python3.12-bookworm-slim` with Node.js 20 for the bridge.

---

## Data Flow Examples

### User sends "Hello" via Telegram

```
1. TelegramChannel receives update from Telegram API
2. _handle_message() checks allow_from → allowed
3. Publishes InboundMessage(channel="telegram", chat_id="12345", content="Hello")
4. AgentLoop.run() consumes from bus.inbound
5. Gets/creates Session("telegram:12345")
6. ContextBuilder assembles system prompt + history + memory
7. provider.chat(messages, tools) → LLM returns text response
8. Session saves turn (append to JSONL)
9. Publishes OutboundMessage(channel="telegram", chat_id="12345", content="Hi there!")
10. ChannelManager routes to TelegramChannel.send()
11. Telegram API delivers message to user
```

### Cron job fires

```
1. CronService timer triggers for job
2. Calls on_job callback → AgentLoop.process_direct(reminder_note)
3. Agent processes with full tool access
4. If job.payload.deliver: publishes OutboundMessage to target channel
```

### Memory consolidation

```
1. After processing a turn, check: unconsolidated messages ≥ memory_window?
2. If yes: call LLM with consolidation prompt + save_memory tool
3. LLM returns tool call: save_memory(history_entry="...", memory_update="...")
4. Append history_entry to HISTORY.md
5. Write memory_update to MEMORY.md
6. Update session.last_consolidated index
```

---

## How to Run

```bash
# Install
pip install nanobot-ai

# First-time setup
nanobot onboard

# Add API key to ~/.nanobot/config.json (e.g., OpenRouter key)

# Chat
nanobot agent -m "Hello!"    # single message
nanobot agent                 # interactive mode

# Multi-channel server
nanobot gateway

# Docker
docker compose up -d nanobot-gateway
```

## Dependencies

Core: typer, litellm, pydantic, httpx, loguru, rich, prompt-toolkit, mcp, croniter
Channels: python-telegram-bot, slack-sdk, qq-botpy, dingtalk-stream, lark-oapi, matrix-nio, websockets
Bridge: @whiskeysockets/baileys, ws, qrcode-terminal
