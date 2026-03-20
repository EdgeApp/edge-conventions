# Venice API + Cursor IDE via LiteLLM Proxy

Venice models with 1M token context windows (e.g. `claude-opus-4-6`, `claude-sonnet-4-6`) fail in Cursor because Cursor derives `max_tokens` from the context window and sends values that exceed Venice's output token limits.

Models with ≤200k context (e.g. `claude-opus-45`) work without a proxy.

LiteLLM sits between Cursor and Venice, clamping `max_tokens` to safe values.

## Prerequisites

- `VENICE_API_KEY` exported in your shell (e.g. in `~/.zshrc`)
- Python 3.10+

## Setup

```bash
pip install 'litellm[proxy]'
pip install python-multipart
```

## Start the proxy

```bash
litellm --config ~/git/edge-conventions/scripts/venice-litellm/litellm-config.yaml --port 8765
```

The config reads your Venice API key from the `VENICE_API_KEY` environment variable via `os.environ/VENICE_API_KEY`, so LiteLLM handles all authentication to Venice directly.

## Configure Cursor

1. Open **Settings > Models**
2. Add custom models by name: `claude-opus-4-6`, `openai-gpt-52`, etc.
3. Set **Override OpenAI Base URL** to `http://localhost:8765`
4. **OpenAI API Key** can be left disabled — LiteLLM already has the Venice key from your environment. If Cursor requires a value, enter any dummy string (e.g. `sk-dummy`).

## Models

All Venice text models are included. Only the 1M-context models need `model_info.max_tokens` to prevent Cursor from over-allocating. The rest pass through unmodified.

### Clamped (1M context — broken without proxy)

| Model | max_tokens | Context |
|-------|------------|---------|
| `claude-opus-4-6` | 8192 | 1M |
| `claude-sonnet-4-6` | 8192 | 1M |
| `gemini-3-1-pro-preview` | 8192 | 1M |

### Pass-through (≤256k context — work without proxy)

| Model | Context | Notes |
|-------|---------|-------|
| `claude-opus-45` | 198k | |
| `claude-sonnet-45` | 198k | |
| `openai-gpt-52` | 256k | |
| `openai-gpt-52-codex` | 256k | Optimized for code |
| `openai-gpt-oss-120b` | 128k | Open-weight MoE |
| `grok-41-fast` | 256k | |
| `grok-code-fast-1` | 256k | Optimized for code |
| `gemini-3-pro-preview` | 198k | |
| `gemini-3-flash-preview` | 256k | |
| `deepseek-v3.2` | 160k | |
| `kimi-k2-thinking` | 256k | |
| `kimi-k2-5` | 256k | |
| `minimax-m21` | 198k | Optimized for code |
| `minimax-m25` | 198k | Optimized for code |
| `zai-org-glm-5` | 198k | |
| `zai-org-glm-4.7` | 198k | |
| `qwen3-coder-480b-a35b-instruct` | 256k | Optimized for code |
| `qwen3-235b-a22b-thinking-2507` | 128k | |
| `qwen3-235b-a22b-instruct-2507` | 128k | |
| `qwen3-vl-235b-a22b` | 256k | Vision-language |
| `llama-3.3-70b` | 128k | |
| `hermes-3-llama-3.1-405b` | 128k | |
| `google-gemma-3-27b-it` | 198k | Vision |

## Adding models

Edit `litellm-config.yaml` following the existing pattern. Use Venice model IDs from their [models endpoint](https://docs.venice.ai/api-reference/endpoint/models/list). Only add `model_info.max_tokens` for models with context windows >256k.

## Why not use Venice directly?

Venice advertises `availableContextTokens: 1000000` for newer Claude/Gemini models. Cursor uses this to budget `max_tokens`, often requesting 200k+ output tokens. Venice rejects these with:

```
max_tokens: 232001 > 128000, which is the maximum allowed number of output tokens for claude-opus-4-6
```

The proxy intercepts this by setting `model_info.max_tokens` per model, which LiteLLM uses to constrain requests.
