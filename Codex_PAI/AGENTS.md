# Codex_PAI Runtime Instructions

This folder contains a Codex-first wrapper that emulates lifecycle hooks and skill routing.

Operational rules:
- Prefer context from `skills/PAI/SKILL.md` and PAI user steering files.
- Treat `Codex_PAI/MEMORY/` as authoritative runtime state.
- Do not require API keys for authentication. Use `codex login` web/device flow.
- Run with approval-aware sandboxing by default.

Wrapper lifecycle phases:
1. SessionStart
2. UserPromptSubmit
3. Stop
4. SessionEnd

Skill routing:
- Load PAI core context on every session start.
- Keep additional skills available on demand from `skills/*/SKILL.md`.

Security:
- Block obviously destructive commands in prompt text unless explicitly confirmed.
- Keep fail-open behavior for non-critical automation hooks.
