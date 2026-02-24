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

## Test Prompt
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