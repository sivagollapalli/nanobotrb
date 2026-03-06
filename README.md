# Nanobotrb

> 🎨 Vibe coded — this entire gem was built through conversational AI pair programming.

A slim Ruby port of [nanobot](https://github.com/HKUDS/nanobot) (Python). The original supports 10+ channels, subagents, cron, MCP, and more. This version strips it down to the essentials: one channel (Telegram), a tool-calling agent loop, and async message passing — just enough to be useful without the complexity.

Connect your favourite LLM to Telegram (more channels coming) and let it answer questions, search the web, read/write files, and run shell commands — all through an async message bus.

## Architecture

```
User (Telegram / CLI)
        │
        ▼
  Channel Layer ──→ MessageBus ──→ AgentLoop ──→ LLM Provider
        ▲               │              │
        │               │         Tool Registry
        └───────────────┘         (web_search, read_file, write_file, exec)
```

- **MessageBus** — async inbound/outbound queues (Async gem)
- **AgentLoop** — consumes messages, builds context, calls LLM with tool-use loop (up to 40 iterations), consolidates memory
- **Channels** — Telegram (via telegram-bot-ruby), with a base class for adding more
- **Provider** — OpenAI-compatible HTTP calls (works with OpenAI, Abacus RouteLLM, any compatible endpoint)
- **Tools** — `web_search` (SerpApi), `read_file`, `write_file`, `exec`
- **Memory** — two-layer persistence (MEMORY.md for long-term facts, HISTORY.md for timestamped logs)
- **Sessions** — JSONL-backed, keyed by `channel:chat_id`

## Installation

```bash
git clone https://github.com/sgollapalli/nanobotrb.git
cd nanobotrb
bundle install
```

## Configuration

Run the onboard command to create the config directory and workspace:

```bash
bundle exec ruby exe/nanobotrb onboard
```

This creates `~/.nanobotrb/config.json`. Edit it with your keys:

```json
{
  "model": "gemini-2.5-pro",
  "temperature": 0.7,
  "max_tokens": 4096,
  "memory_window": 100,
  "max_iterations": 40,
  "providers": {
    "openai": {
      "api_key": "your-api-key",
      "api_base": "URL"
    }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "token": "your-telegram-bot-token",
      "allow_from": ["*"]
    }
  },
  "tools": {
    "serpapi_key": "your-serpapi-key",
    "exec_timeout": 30,
    "restrict_to_workspace": true
  }
}
```

You can also use environment variables instead:

```bash
export OPENAI_API_KEY="sk-..."        # or ABACUS_KEY for RouteLLM
export TELEGRAM_BOT_TOKEN="123:ABC..."
export SERPAPI_KEY="..."
```

## Usage

### CLI — single message

```bash
bundle exec ruby exe/nanobotrb agent -m "What is the latest Ruby version?"
```

### CLI — interactive chat

```bash
bundle exec ruby exe/nanobotrb agent
```

### Telegram gateway

```bash
bundle exec ruby exe/nanobotrb gateway
```

Then message your bot on Telegram. Special commands:

| Command | Action |
|---------|--------|
| `/new`  | Clear session, start fresh |
| `/stop` | Stop the agent |
| `/help` | Show available tools and commands |

### Other commands

```bash
bundle exec ruby exe/nanobotrb status    # show config and provider status
bundle exec ruby exe/nanobotrb version   # show version
```

## Tools

The agent has access to these tools and will use them automatically when needed:

| Tool | Description |
|------|-------------|
| `web_search` | Google search via SerpApi for up-to-date information |
| `read_file` | Read file contents |
| `write_file` | Create or write files |
| `exec` | Run shell commands (with timeout and safety guards) |

## Development

```bash
bundle install
bundle exec rake test
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
