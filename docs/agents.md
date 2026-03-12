# Optimized Agent Definitions

## Why Custom Agents Matter

GG Coder's subagent tool spawns isolated child processes to handle tasks in parallel. By default, it has no built-in agent definitions — subagents inherit the parent's model and full system prompt, which is wasteful for simple tasks.

Custom agent definitions let you:
- **Route cheap tasks to cheap models** — a file search doesn't need Opus
- **Restrict tools** — read-only agents can't accidentally edit files
- **Constrain behavior** — tool call limits and output format rules prevent runaway costs
- **Run parallel work** — spawn multiple forks, each handling one unit of work

## The Four Agents

### scout (Haiku)

Read-only codebase reconnaissance. Grep, find, read — nothing else. Hardcoded to Haiku (cheapest model) because searching files doesn't need intelligence, it needs speed.

Key constraint: **10 tool call limit** in the prompt. This prevents Haiku from thrashing through unnecessary calls when it can't find something.

```
Tools: read, grep, find, ls, bash
Model: claude-haiku-4-5-20251001
```

### runner (Haiku)

Execute a command and report the result. Two tools: `bash` and `read`. That's it. Never fixes anything, never modifies files. Pure observation.

```
Tools: bash, read
Model: claude-haiku-4-5-20251001
```

### worker (inherits parent model)

Full capability for complex multi-step tasks — exploring code, making edits, running verification. Use when the job needs 5+ tool calls and involves both reading and writing.

Capped at 30 turns to prevent runaway sessions. Cannot spawn sub-agents (no recursion).

```
Tools: bash, read, write, edit, grep, find, ls
Model: inherit (uses parent's model)
Max turns: 30
```

### fork (inherits parent model)

Isolated parallel worker with strict structured output. When you need 5 things done independently, spawn 5 forks. Each reports back in a fixed format:

```
Scope: <what was assigned>
Result: <findings or outcome>
Key files: <absolute paths>
Files changed: <with commit hash>
Issues: <if any>
```

Capped at 30 turns. No sub-agents, no conversation, no editorializing.

```
Tools: bash, read, write, edit, grep, find, ls
Model: inherit (uses parent's model)
Max turns: 30
```

## Token Optimization: CLAUDE.md

The included `CLAUDE.md` template replaces verbose model routing tables (~300 tokens) with two lines:

```markdown
## Subagent Routing
- Use the model specified in each agent's definition. Don't override.
- If a subagent returns confused or low-quality results, escalate one tier up.
```

The old approach listed every model tier with bullet points of when to use each. But the agent definitions already specify their models — the routing table was redundant overhead processed on every single turn.

## Installation

```bash
bash <(curl -sL https://raw.githubusercontent.com/creativeprofit22/ggcoder-fixes/main/scripts/install-agents.sh)
```

Or from a cloned repo:

```bash
bash scripts/install-agents.sh
```

Files are installed to:
- `~/.gg/agents/` — agent definitions (scout, runner, worker, fork)
- `~/CLAUDE.md` — optimized config (only if one doesn't already exist)

## Customizing

Agent files are plain markdown with YAML frontmatter. Edit them directly:

```bash
vim ~/.gg/agents/worker.md
```

Available frontmatter fields:

| Field | Description |
|-------|-------------|
| `name` | Agent name (used in subagent tool) |
| `description` | Shown in tool description |
| `tools` | Comma-separated tool whitelist |
| `model` | Model ID, `inherit`, `haiku`, or `sonnet` |
| `max-turns` | Maximum LLM calls before stopping |

The body of the markdown becomes the agent's system prompt.
