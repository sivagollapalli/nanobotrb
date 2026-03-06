# Nanobotrb Architecture

> 🎨 Vibe coded Ruby port of [nanobot](https://github.com/liunux4odoo/nanobot) (Python).
> Slimmed down to the essentials: Telegram channel, tool-calling agent loop, async message bus.

## Overview

Nanobotrb is a lightweight AI assistant framework in Ruby. It connects to Telegram, routes messages through an async bus to a central agent loop, calls any OpenAI-compatible LLM with tool-use capabilities, and sends responses back.

```
┌───────────────────────────────────────┐
│               User                    │
│       Telegram │ CLI                  │
└─────────┬──────┴──┬──────────────────┘
          │         │
          ▼         ▼
┌───────────────────────────────────────┐
│           Channel Layer               │
│  BaseChannel → TelegramChannel        │
│  - Permission checks (allow_from)     │
│  - Message parsing                    │
└──────────────┬────────────────────────┘
               │ InboundMessage
               ▼
┌───────────────────────────────────────┐
│           MessageBus                  │
│  Two Async queues:                    │
│  - inbound:  Channel → Agent          │
│  - outbound: Agent → Channel          │
└──────────────┬────────────────────────┘
               │
               ▼
┌───────────────────────────────────────┐
│           AgentLoop                   │
│  1. Consume message from bus          │
│  2. Build context (prompt + history)  │
│  3. Call LLM with tools               │
│  4. Execute tool calls (max 40 iter)  │
│  5. Consolidate memory if needed      │
│  6. Publish response to bus           │
└───┬────────┬────────┬────────┬───────┘
    │        │        │        │
    ▼        ▼        ▼        ▼
 Provider  Tools   Memory   Sessions
```

## What's different from the Python original

| Feature | Python nanobot | nanobotrb |
|---|---|---|
| Channels | 10+ (Telegram, Discord, WhatsApp, Slack, etc.) | Telegram + CLI |
| Async | asyncio | Async gem (fiber-based) |
| LLM | LiteLLM with provider registry | Direct OpenAI-compatible HTTP |
| Tools | 10+ including MCP, spawn, cron | 4 (web_search, read_file, write_file, exec) |
| Subagents | Yes (spawn tool) | Not implemented |
| Cron | Yes (at/every/cron) | Not implemented |
| Heartbeat | Yes | Not implemented |
| Skills | Markdown-based progressive loading | Not implemented |
| MCP | stdio + HTTP transports | Not implemented |

---

## Project Structure

```
lib/nanobotrb/
├── bus/
│   ├── message_bus.rb      # Async inbound/outbound queues
│   └── messages.rb         # InboundMessage / OutboundMessage data classes
├── channels/
│   ├── base.rb             # BaseChannel with permission checks
│   ├── manager.rb          # Routes outbound messages to channels
│   └── telegram.rb         # Telegram bot via telegram-bot-ruby
├── agent/
│   ├── loop.rb             # Core processing engine
│   ├── context_builder.rb  # System prompt assembly
│   ├── memory.rb           # MEMORY.md + HISTORY.md persistence
│   └── tools/
│       ├── base.rb         # Tool ABC
│       ├── registry.rb     # Central tool registry
│       ├── web_search.rb   # Google search via SerpApi
│       ├── read_file.rb    # File reading
│       ├── write_file.rb   # File writing
│       └── exec.rb         # Shell command execution
├── providers/
│   ├── base.rb             # LLMResponse data class + provider ABC
│   └── ruby_llm_provider.rb  # Direct OpenAI-compatible HTTP calls
├── session/
│   └── manager.rb          # JSONL session storage
├── config.rb               # JSON config with defaults
├── cli.rb                  # Thor CLI
└── version.rb
```

---

## Entry Points

Two execution modes via Thor CLI:

| Command | What it does |
|---|---|
| `nanobotrb agent` | Interactive CLI chat (or single-shot with `-m "message"`) |
| `nanobotrb gateway` | Telegram bot server: starts channel + agent loop |
| `nanobotrb onboard` | First-time setup: creates `~/.nanobotrb/` |
| `nanobotrb status` | Shows config, provider keys, channel status |
| `nanobotrb version` | Shows version |

### How `agent` works

```ruby
# Single message mode
nanobotrb agent -m "What's the weather?"
# → Creates AgentLoop, calls process_direct(), prints response, exits

# Interactive mode
nanobotrb agent
# → Creates AgentLoop + MessageBus
# → Reads from stdin, publishes to bus, prints outbound responses
```

### How `gateway` works

```ruby
Async do |task|
  task.async { agent_loop.run }           # AgentLoop consuming from bus
  task.async { channel_manager.start_all } # Telegram + outbound dispatcher
end
```

---

## Core Components

### 1. MessageBus (`bus/message_bus.rb`)

Decoupling layer between channels and the agent. Two queues backed by arrays + `Async::Condition` for signaling:

- `inbound`: Channels push `InboundMessage` (channel, sender_id, chat_id, content, media, metadata)
- `outbound`: Agent pushes `OutboundMessage` (channel, chat_id, content, reply_to, media)

Messages are Ruby `Data.define` value objects (immutable).

### 2. Channel System (`channels/`)

`BaseChannel` provides:
- `start` / `stop` / `send_message` interface
- `allowed?(sender_id)` permission check via `allow_from` list
- `publish_inbound` helper that checks permissions before pushing to bus

`TelegramChannel` uses `telegram-bot-ruby` gem:
- Long-polling via `bot.listen`
- Markdown message sending with fallback to plain text
- Message splitting for Telegram's 4096 char limit
- Metadata extraction (username, message_id)

`ChannelManager` registers channels and dispatches outbound messages to the correct one.

### 3. AgentLoop (`agent/loop.rb`)

The core processing engine. For each inbound message:

```
1. Get/create session (keyed by channel:chat_id)
2. Handle special commands (/new, /stop, /help)
3. Build context via ContextBuilder
4. LLM call loop (up to max_iterations=40):
   a. Call provider.chat(messages, tools)
   b. If response has tool_calls → execute each via ToolRegistry
   c. Append tool results to messages
   d. Repeat until no more tool calls or max iterations
5. Save turn to session (append-only JSONL)
6. Consolidate memory if unconsolidated messages ≥ memory_window
7. Publish OutboundMessage to bus
```

### 4. ContextBuilder (`agent/context_builder.rb`)

Assembles the system prompt:

```
Runtime info (time, version)
  + Guidelines
  + Long-term memory (MEMORY.md)
```

Builds user messages with runtime context (current time, channel, chat_id).

### 5. Memory System (`agent/memory.rb`)

Two-layer persistent memory:

- `MEMORY.md` — Long-term facts (updated via LLM consolidation)
- `HISTORY.md` — Timestamped conversation summaries

Consolidation triggers when unconsolidated messages exceed `memory_window` (default 100). The LLM summarizes old messages and the result is appended to HISTORY.md.

### 6. Session Management (`session/manager.rb`)

- Sessions stored as JSONL files (one message per line)
- Key format: `channel:chat_id` (e.g., `telegram:12345`)
- Tracks `last_consolidated` index for memory consolidation offset
- `get_history()` returns unconsolidated messages, aligned to start at a user turn
- Metadata stored in separate `.meta.json` files

### 7. Provider (`providers/ruby_llm_provider.rb`)

Direct HTTP calls to any OpenAI-compatible endpoint (no RubyLLM chat abstraction):

- Sends `system`, `user`, `assistant`, `tool` roles directly
- System prompt folded into first user message to avoid `developer` role issues with some endpoints
- Full tool-calling protocol: sends tool definitions, parses `tool_calls` responses
- Works with OpenAI, Abacus RouteLLM, or any compatible API

`LLMResponse` contains: content, tool_calls, finish_reason, usage.

### 8. Tool System (`agent/tools/`)

Tools extend `Base` with `name`, `description`, `parameters` (JSON Schema), and `execute`:

| Tool | What it does |
|---|---|
| `web_search` | Google search via SerpApi for up-to-date information |
| `read_file` | Read file contents (truncates at 100KB) |
| `write_file` | Write/create files (creates directories as needed) |
| `exec` | Shell command execution (timeout, dangerous command blocking) |

`Registry` provides `register()`, `definitions` (for LLM), `execute(name, **args)`.

---

## Configuration

Config file: `~/.nanobotrb/config.json`

```
Config
├── model, temperature, max_tokens, memory_window, max_iterations
├── providers
│   └── openai (api_key, api_base)
├── channels
│   └── telegram (enabled, token, allow_from)
└── tools (serpapi_key, exec_timeout, restrict_to_workspace)
```

Workspace: `~/.nanobotrb/workspace/` (sessions/, memory/)

---

## Data Flow: User sends "Hello" via Telegram

```
1. TelegramChannel receives update via long-polling
2. handle_message() checks allow_from → allowed
3. Publishes InboundMessage(channel: "telegram", chat_id: "12345", content: "Hello")
4. AgentLoop.run consumes from bus.inbound
5. Gets/creates Session("telegram:12345")
6. ContextBuilder assembles system prompt + history + memory
7. provider.chat(messages, tools) → HTTP POST to LLM endpoint
8. LLM returns text response (or tool_calls → execute → loop)
9. Session saves turn (append to JSONL)
10. Publishes OutboundMessage(channel: "telegram", chat_id: "12345", content: "Hi!")
11. ChannelManager routes to TelegramChannel.send_message
12. Telegram API delivers message to user
```

---

## Dependencies

Core: async, thor, json, logger, net/http
Channel: telegram-bot-ruby
Search: serpapi
