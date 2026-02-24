# Codex_PAI

Codex_PAI is a standalone wrapper that brings PAI-style lifecycle automation to Codex CLI without API keys.

## Key points
- Uses **web login only** (`codex login`, ChatGPT auth)
- Adds lifecycle hooks: SessionStart, UserPromptSubmit, Stop, SessionEnd
- Preserves memory/state in `Codex_PAI/MEMORY/`
- Works in two modes:
  - `chat`: multi-turn wrapper loop over `codex exec`
  - `exec`: one-shot wrapped execution

## Quick start
```bash
cd /home/postnl/PAI_Codex/Codex_PAI
./bin/codex-pai status
./bin/codex-pai chat
```

## Run From Any Location
`Codex_PAI` can be moved anywhere. Set `PAI_ROOT` to your main PAI root:

```bash
export PAI_ROOT=/home/postnl/PAI_Codex/Codex_PAI
```

If `PAI_ROOT` is not set, wrapper auto-detects in this order:
- Adjacent parent of `Codex_PAI`
- `/home/postnl/PAI_Codex/Codex_PAI`

## Commands
- `codex-pai chat [--model MODEL] [--search] [--cd DIR]`
- `codex-pai exec "prompt" [--model MODEL] [--search] [--cd DIR]`
- `codex-pai start [codex interactive args...]`
- `codex-pai status`

## What is emulated
- Session start banner + context cache + version check
- Prompt submission logic: rating capture, session naming, work creation, security gate
- Stop logic: response capture + optional voice notification
- Session end logic: summary, learning files, counts, integrity hashes

## Limitations
- Codex CLI does not expose Claude-style native per-tool lifecycle hooks, so PreToolUse/PostToolUse are emulated at prompt/response boundaries.
- Native tab-color changes are represented in state files (`MEMORY/STATE/tab-state.json`) unless a terminal integration is added.

## How To Use
```bash
# 1) Login once (web auth, no API key)
codex login

# 2) Go to the app directory
cd /home/postnl/PAI_Codex/Codex_PAI

# 3) Verify setup
./bin/codex-pai status

# 4) Run interactive mode
./bin/codex-pai chat

# 5) Or run one-shot mode
./bin/codex-pai exec "your prompt here"
```

EXAMPLE:

PROMPT=$(cat <<'EOF'
Research REGN financials.
Use latest available filings and earnings materials.
Return:
1) Revenue, operating income, net income trend (last 8 quarters)
2) North America vs International contribution
3) Free cash flow trend and main drivers
4) Balance sheet health (cash, debt, leases)
5) Valuation snapshot (P/E, EV/EBITDA, FCF yield) with caveats
6) Key risks and 3 bull/base/bear scenarios for next 12 months.
Cite sources with links and dates.
Save output as a .md file into the Research folder.
EOF
)

./bin/codex-pai exec "$PROMPT" --search --model gpt-5.3-codex
## Agent Wrappers
`agents/` profiles can be used through wrappers in `bin/`.

Generated commands:
- `agent-run` (generic): select agent by name
- `agent-algorithm`
- `agent-architect`
- `agent-artist`
- `agent-claude-researcher`
- `agent-codex-researcher`
- `agent-designer`
- `agent-engineer`
- `agent-gemini-researcher`
- `agent-grok-researcher`
- `agent-intern`
- `agent-pentester`
- `agent-perplexity-researcher`
- `agent-q-a-tester`

Usage examples:

```bash
# Generic wrapper
./bin/agent-run Engineer "Review scripts/session_exec.sh for reliability issues" --model gpt-5.3-codex

# Specific wrapper
./bin/agent-engineer "Audit the wrapper for shell parsing bugs and propose patches" --search --model gpt-5.3-codex

# Another specific wrapper
./bin/agent-architect "Propose a cleaner lifecycle architecture for hooks and memory" --model gpt-5.3-codex
```

Notes:
- First argument is the task prompt for specific wrappers.
- Additional flags are passed through to `codex-pai exec`.
- Agent wrappers inject the selected `agents/<Name>.md` profile into the prompt before execution.

## Using A Skill + Agent Together (Example: VRTX)
Use both by combining:
- an **agent wrapper** (role/personality from `agents/*.md`), and
- an explicit **skill instruction** in your task prompt (for example the `Research` skill workflow style).

Pattern:
1. Pick an agent wrapper (e.g., `agent-codex-researcher` or `agent-architect`).
2. In the prompt, explicitly instruct it to use the Research skill workflow.
3. Request output file location and citation requirements.

Example (VRTX):

```bash
PROMPT=$(cat <<'EOF2'
Use the Research skill workflow to investigate VRTX (Vertex Pharmaceuticals) financials.

Requirements:
1) Revenue, operating income, net income trend (last 8 quarters)
2) Geographic contribution (US vs international when available)
3) Free cash flow trend and main drivers
4) Balance sheet health (cash, debt, lease liabilities)
5) Valuation snapshot (P/E, EV/EBITDA, FCF yield) with caveats
6) Key risks and 12-month bull/base/bear scenarios

Use latest available filings and earnings materials.
Cite sources with links and dates.
Create Research/VRTX_financials_$(date +%F).md.
EOF2
)

./bin/agent-codex-researcher "$PROMPT" --search --model gpt-5.3-codex
```

Alternative generic form:

```bash
./bin/agent-run CodexResearcher \
"Use the Research skill workflow to analyze VRTX financials with citations and save to Research/VRTX_financials_$(date +%F).md" \
--search --model gpt-5.3-codex
```

How to confirm it worked:
- Check output file: `ls -la Research/VRTX_financials_*.md`
- Check session transcript: `MEMORY/SESSIONS/<session_id>/transcript.jsonl`
- Check strict skill confirmations: `MEMORY/STATE/skills-used.jsonl`
- Check strict agent confirmations: `MEMORY/STATE/agents-used.jsonl`



check if skill has been used:
 tail -n 50 /home/postnl/PAI_Codex/Codex_PAI/MEMORY/STATE/skills-used.jsonl
## Skill Enforcement (Strict)
When your prompt explicitly requests a skill (for example, "Use the Research skill workflow"), the wrapper now enforces it.

Behavior:
1. Detect requested skill from prompt text.
2. Inject mandatory contract into model prompt.
3. Require first output line to be exactly:
   `Running the **<Skill>** workflow in the **<Skill>** skill.`
4. If missing, auto-retry once with stronger instruction.
5. If still missing:
   - `exec` mode exits with failure status
   - `chat` mode rejects that response and continues

Audit logs:
- Requested-vs-confirmed contract log:
  - `MEMORY/STATE/skill-contracts.jsonl`
- Strict confirmed skill usage log:
  - `MEMORY/STATE/skills-used.jsonl`

## Template Enforcement (Opt-In)
By default, you can define any deliverable structure in your prompt.

If you want strict template enforcement, add one of these lines to your prompt:
- `Template: skills/Research/Templates/MarketResearch.md`
- `Use template: skills/Research/Templates/MarketResearch.md`

Behavior when template is requested:
1. Wrapper resolves the template file path.
2. Wrapper injects a template contract into the model prompt.
3. Response is validated against required template headings.
4. If invalid, wrapper retries once.
5. If still invalid:
- `exec` mode exits with contract failure
- `chat` mode rejects the response and continues

Template audit log:
- `MEMORY/STATE/template-contracts.jsonl`

## Agent Usage Logging (Strict)
When you run via an agent wrapper (`agent-run` or `agent-*`), agent usage is logged to:
- `MEMORY/STATE/agents-used.jsonl`

Quick check:
```bash
tail -n 5 MEMORY/STATE/agents-used.jsonl
```

Quick example

PROMPT=$(cat <<'EOF'
Use the Research skill workflow.
Template: skills/Research/Templates/MarketResearch.md
Analyze VRTX and save to Research/VRTX_template_test_$(date +%F).md
EOF
)

./bin/codex-pai exec "$PROMPT" --search --model gpt-5.3-codex
tail -n 5 MEMORY/STATE/template-contracts.jsonl


## Test Prompt Skill enforced
• PROMPT=$(cat <<'EOF'
  Use the Research skill workflow to analyze VRTX financials.

  Requirements:
  1) Revenue, operating income, net income trend (last 8 quarters)
  2) Geographic contribution (US vs international where available)
  3) Free cash flow trend and key drivers
  4) Balance sheet health (cash, debt, leases)
  5) Valuation snapshot (P/E, EV/EBITDA, FCF yield) with caveats
  6) Top risks and 12-month bull/base/bear scenarios

  Use latest filings and earnings materials.
  Cite each source with link and date.
  Save output to Research/VRTX_financials_$(date +%F).md.
  EOF
  )

  ./bin/codex-pai exec "$PROMPT" --search --model gpt-5.3-codex

  After it finishes, verify enforcement logs:

  tail -n 5 MEMORY/STATE/skill-contracts.jsonl
  tail -n 5 MEMORY/STATE/skills-used.jsonl
  
## Test Prompt Skill and Agent enforced  
PROMPT=$(cat <<'EOF'
Use the Research skill workflow to investigate GILD (Gilead Sciences).
Operate as a CodexResearcher agent: be evidence-first, cite primary sources, and highlight assumptions.

Deliver:
1) Revenue, operating income, and net income trend (last 8 quarters)
2) US vs international contribution (or best available geographic proxy)
3) Free cash flow trend and main drivers
4) Balance sheet health: cash, debt, lease liabilities
5) Valuation snapshot: P/E, EV/EBITDA, FCF yield (state caveats)
6) Key risks and 12-month bull/base/bear scenarios

Use latest filings and earnings materials.
Cite sources with direct links and dates.
Save as Research/GILD_agent_skill_$(date +%F).md.
EOF
)

  ./bin/agent-codex-researcher "$PROMPT" --search --model gpt-5.3-codex


## CODE REVIEW:
• Findings (highest severity first)

  - High: Path traversal in upload API allows writes outside Telos directory via crafted filename.
    File: skills/Telos/DashboardTemplate/App/api/upload/route.ts:49 (/home/postnl/PAI_Codex/Codex_PAI/skills/Telos/DashboardTemplate/
    App/api/upload/route.ts:49), skills/Telos/DashboardTemplate/App/api/upload/route.ts:52 (/home/postnl/PAI_Codex/Codex_PAI/skills/
    Telos/DashboardTemplate/App/api/upload/route.ts:52), skills/Telos/DashboardTemplate/App/api/upload/route.ts:64 (/home/postnl/
    PAI_Codex/Codex_PAI/skills/Telos/DashboardTemplate/App/api/upload/route.ts:64)
  - High: Path traversal in file-save API allows overwrite outside Telos directory via filename in JSON body.
    File: skills/Telos/DashboardTemplate/App/api/file/save/route.ts:25 (/home/postnl/PAI_Codex/Codex_PAI/skills/Telos/DashboardTemplate/
    App/api/file/save/route.ts:25), skills/Telos/DashboardTemplate/App/api/file/save/route.ts:27 (/home/postnl/PAI_Codex/Codex_PAI/
    skills/Telos/DashboardTemplate/App/api/file/save/route.ts:27), skills/Telos/DashboardTemplate/App/api/file/save/route.ts:39 (/home/
    postnl/PAI_Codex/Codex_PAI/skills/Telos/DashboardTemplate/App/api/file/save/route.ts:39)
  - High: Hooks resolve to ~/.claude when PAI_DIR is unset, but wrapper scripts do not export PAI_DIR; this can make hooks operate on
    the wrong tree.
    File: hooks/lib/paths.ts:33 (/home/postnl/PAI_Codex/Codex_PAI/hooks/lib/paths.ts:33), hooks/lib/paths.ts:39 (/home/postnl/PAI_Codex/
    Codex_PAI/hooks/lib/paths.ts:39), scripts/common.sh:28 (/home/postnl/PAI_Codex/Codex_PAI/scripts/common.sh:28), bin/codex-pai:26 (/
    home/postnl/PAI_Codex/Codex_PAI/bin/codex-pai:26)
  - High: Stop-hook rebuild logic hard-codes ~/.claude/skills/PAI, bypassing active repo root and breaking portability/consistency.
    File: hooks/handlers/RebuildSkill.ts:27 (/home/postnl/PAI_Codex/Codex_PAI/hooks/handlers/RebuildSkill.ts:27), hooks/handlers/
    RebuildSkill.ts:72 (/home/postnl/PAI_Codex/Codex_PAI/hooks/handlers/RebuildSkill.ts:72)
  - Medium: Identity loader always reads ~/.claude/settings.json, ignoring active PAI location, so persona/voice settings can be stale
    or wrong.
    File: hooks/lib/identity.ts:13 (/home/postnl/PAI_Codex/Codex_PAI/hooks/lib/identity.ts:13)
  - Medium: session_exec.sh swallows codex exec failure and can still print success/continue flow.
    File: scripts/session_exec.sh:88 (/home/postnl/PAI_Codex/Codex_PAI/scripts/session_exec.sh:88), scripts/session_exec.sh:155 (/home/
    postnl/PAI_Codex/Codex_PAI/scripts/session_exec.sh:155)
  - Medium: Multiple agent launcher scripts hard-code absolute repo path, so cloned/moved installs break.
    File: bin/agent-run:4 (/home/postnl/PAI_Codex/Codex_PAI/bin/agent-run:4), bin/agent-algorithm:4 (/home/postnl/PAI_Codex/Codex_PAI/
    bin/agent-algorithm:4) (and other bin/agent-*)
  - Medium: LoadContext rebuild command hard-codes absolute path instead of paiDir, reducing portability.
    File: hooks/LoadContext.hook.ts:523 (/home/postnl/PAI_Codex/Codex_PAI/hooks/LoadContext.hook.ts:523)
  - Medium: Security guard relies on a short literal pattern list; easy bypasses and false sense of protection for destructive intent.
    File: config/wrapper.json:34 (/home/postnl/PAI_Codex/Codex_PAI/config/wrapper.json:34), scripts/security_guard.sh:14 (/home/postnl/
    PAI_Codex/Codex_PAI/scripts/security_guard.sh:14)
  - Medium: Automated test coverage is effectively absent for wrapper/hook critical paths.
    File examples: scripts/session_chat.sh (/home/postnl/PAI_Codex/Codex_PAI/scripts/session_chat.sh), scripts/session_exec.sh (/home/
    postnl/PAI_Codex/Codex_PAI/scripts/session_exec.sh), hooks/StopOrchestrator.hook.ts (/home/postnl/PAI_Codex/Codex_PAI/hooks/
    StopOrchestrator.hook.ts)

  Open questions / assumptions

  - I assumed Telos dashboard routes are reachable by users beyond fully trusted local-only operators; if true, those traversal issues
    are urgent.
  - I reviewed executable code surfaces (bin/, scripts/, hooks/, executable code under skills/) rather than markdown/doc content.



## To continue this session, run codex resume 019c8f30-0df8-77e0-b6c0-9eaee890f9f2