• Shortest path with Codex CLI is to treat it as a runtime + wrapper problem.

  1. Create a codex-launch wrapper.

  - Run “SessionStart” actions before codex starts (banner, context load, env checks).
  - Run “SessionEnd” actions after exit (summary, counts, integrity, memory writes).

  2. Move PreToolUse controls into Codex permissions/policy.

  - Use sandbox + approval rules for dangerous commands/paths.
  - Keep a custom security checker script for extra validation before destructive ops.

  3. Put hook logic into reusable scripts.

  - hooks/start/*.ts for startup tasks.
  - hooks/stop/*.ts for post-response/session tasks.
  - hooks/end/*.ts for end-of-session persistence.

  4. Recreate “skills” via routing in AGENTS.md.

  - Keep skills/*/SKILL.md.
  - Add deterministic trigger rules in AGENTS.md (“if request matches X, load skill Y”).
  - This gives you skill behavior without native Claude-style Skill hook events.

  5. Add transcript/log pipeline.

  - Capture codex session output to JSONL/markdown.
  - Run post-processors for ratings, learnings, relationship notes, and counts.

  Important limitation:

  - Claude-style native lifecycle hooks (PreToolUse, PostToolUse, Stop) are not 1:1 in Codex CLI, so you emulate
    them with wrappers and policy gates. You can get most of the value, but not identical interception
    granularity.

  If you want, I can scaffold this release with:

  1. scripts/codex-launch.sh
  2. hooks/start|stop|end/ runners
  3. AGENTS.md skill-router block
  4. MEMORY post-session processors