#!/usr/bin/env bash
# duncemode-detect.sh — Claude Code UserPromptSubmit hook
#
# Scans incoming user prompts for duncemode trigger phrases, maintains state
# in ~/.claude/state/duncemode.json, and injects a system line into Claude's
# context telling it what mode to run in.
#
# Wire up in ~/.claude/settings.json:
#   { "hooks": { "UserPromptSubmit": [
#       { "command": "bash",
#         "args": ["~/.claude/skills/duncemode/hooks/duncemode-detect.sh"] }
#   ] } }
#
# Requires: bash, jq, grep. No other dependencies.

set -euo pipefail

STATE_DIR="${HOME}/.claude/state"
STATE_FILE="${STATE_DIR}/duncemode.json"
mkdir -p "$STATE_DIR"

# Read hook input (JSON on stdin; we only need .user_message)
INPUT="$(cat)"
MESSAGE="$(echo "$INPUT" | jq -r '.user_message // .prompt // ""')"

# Lowercase for matching
MSG_LC="$(echo "$MESSAGE" | tr '[:upper:]' '[:lower:]')"

# Read current state (default: off)
if [[ -f "$STATE_FILE" ]]; then
  CURRENT_MODE="$(jq -r '.mode // "off"' "$STATE_FILE" 2>/dev/null || echo "off")"
else
  CURRENT_MODE="off"
fi

# --- Trigger categories ------------------------------------------------------
# Each category is a pipe-separated list of regex alternatives. Word boundaries
# are added where appropriate to reduce false positives.

TOGGLE_ON_RE='\bduncemode (on|enable)\b|\bturn on duncemode\b|\benable duncemode\b'
TOGGLE_OFF_RE='\bduncemode (off|disable|normal)\b|\bturn off duncemode\b|\bdisable duncemode\b'
TOGGLE_ALL_RE='\bduncemode (all|full|deep)\b'
TOGGLE_STATUS_RE='\bduncemode status\b'

# Bullshit family — always escalate to `all`
BULLSHIT_RE='\bbullshit\b|/bullshit\b|\bcall bullshit\b|\bthat.?s bs\b|\btotal bullshit\b|\bcomplete bullshit\b|\bwhat a load of bullshit\b'

# Disbelief / verification demand
DISBELIEF_RE='\breally\?|\bseriously\?|\bare you sure\b|\bare you certain\b|\bdid you actually\b|\bdid you really\b|\bprove it\b|\bshow me\b|\bshow your work\b|\breceipts\b|\bi don.?t believe you\b|\bthat can.?t be right\b|\bthat doesn.?t sound right\b|\bverify that\b'

# Accusation of wrongness or fabrication
ACCUSATION_RE='\bthat.?s wrong\b|\byou.?re wrong\b|\bthat.?s incorrect\b|\bno that.?s not right\b|\byou lied\b|\byou made that up\b|\byou.?re making this up\b|\byou.?re hallucinating\b|\bhallucination\b|\byou fabricated\b|\bconfabulating\b|\bthat.?s lazy\b|\blazy answer\b|\blow effort\b|\bhalf.?assed\b|\byou didn.?t actually\b'

# Think harder
THINK_HARDER_RE='\bthink harder\b|\bthink deeper\b|\bdig deeper\b|\blook deeper\b|\btrace it\b|\bend to end\b|\brubber duck\b|\brubber ducky\b|\bdebug it properly\b|\blook again\b|\btry again properly\b|\bdo it right\b|\bstop being lazy\b|\bdo the work\b'

# Frustration — profanity / exclamations
PROFANITY_RE='\bwtf\b|\bwhat the fuck\b|\bwhat the hell\b|\bwth\b|\bffs\b|\bfor fuck.?s sake\b|\bjesus christ\b|\bjfc\b|\bgod damn it\b|\bgoddamn|\bfucking hell\b|\bbloody hell\b'

# Frustration — name-calling
NAMECALL_RE='\bstupid\b|\bdumb\b|\bidiot\b|\bmoron\b|\bdense\b|\buseless\b|\bbroken\b|\bgarbage\b|\btrash\b|\bpathetic\b|\bincompetent\b|\bretarded\b|\blazy\b|\byou.?re lazy\b|\bbeing lazy\b|\bso lazy\b|\btoo lazy\b|\bwhat a lazy\b'

# Frustration — Australian vernacular
AUSSIE_RE='\bbloody oath\b|\byou bloody\b|\bbloody useless\b|\bnot bloody likely\b|\brooted\b|\bcooked\b|\bstuffed\b|\bbuggered\b|\bwanker\b|\bdrongo\b|\bdropkick\b|\bgalah\b|\bmuppet\b|\bpillock\b|\bcrack the shits\b|\bspat the dummy\b|\bchucked a wobbly\b|\bfair dinkum\b|\byou.?re having a laugh\b|\byou.?re joking\b|\bpull the other one\b|\bfair crack of the whip\b|\bgive it a red.?hot go\b'

# Escalation — user repeating themselves
ESCALATION_RE='\bstill wrong\b|\bstill broken\b|\bstill not working\b|\bstill doesn.?t work\b|\bi told you\b|\bi already said\b|\bi just said\b|\bsame thing\b|\byou.?re not listening\b|\bread what i said\b'

# --- Match logic -------------------------------------------------------------

match() {
  echo "$MSG_LC" | grep -qEi "$1"
}

NEW_MODE="$CURRENT_MODE"
REASON=""

# Explicit toggles take priority over everything else
if match "$TOGGLE_OFF_RE"; then
  NEW_MODE="off"
  REASON="explicit toggle off"
elif match "$TOGGLE_ALL_RE"; then
  NEW_MODE="all"
  REASON="explicit toggle all"
elif match "$TOGGLE_ON_RE"; then
  NEW_MODE="on"
  REASON="explicit toggle on"
elif match "$TOGGLE_STATUS_RE"; then
  # No state change, just report
  REASON="status query"

# Bullshit family — always jump to all
elif match "$BULLSHIT_RE"; then
  NEW_MODE="all"
  REASON="bullshit family trigger"

# Escalation markers — force all if already on, else jump to on
elif match "$ESCALATION_RE"; then
  if [[ "$CURRENT_MODE" == "on" || "$CURRENT_MODE" == "all" ]]; then
    NEW_MODE="all"
    REASON="escalation: user repeating themselves while already active"
  else
    NEW_MODE="on"
    REASON="escalation marker from cold"
  fi

# Frustration / accusation / disbelief / think-harder / aussie vernacular — activate or escalate
elif match "$NAMECALL_RE" || match "$PROFANITY_RE" || match "$AUSSIE_RE" || match "$ACCUSATION_RE" || match "$DISBELIEF_RE" || match "$THINK_HARDER_RE"; then
  if [[ "$CURRENT_MODE" == "off" ]]; then
    NEW_MODE="on"
    REASON="frustration/disbelief/think-harder trigger from off"
  elif [[ "$CURRENT_MODE" == "on" ]]; then
    NEW_MODE="all"
    REASON="frustration persisting while already on — escalating to all"
  fi
fi

# --- Persist state and emit context injection -------------------------------

if [[ "$NEW_MODE" != "$CURRENT_MODE" ]] || [[ -n "$REASON" ]]; then
  TS="$(date -Iseconds)"
  jq -n \
    --arg mode "$NEW_MODE" \
    --arg prev "$CURRENT_MODE" \
    --arg reason "$REASON" \
    --arg ts "$TS" \
    '{mode:$mode, previous_mode:$prev, last_reason:$reason, updated_at:$ts}' \
    > "$STATE_FILE"
fi

# Emit the system line on stdout — Claude Code will inject this into context.
# Always emit something so Claude can see current state, even if unchanged.
ANNOUNCE=""
if [[ "$CURRENT_MODE" == "off" && ("$NEW_MODE" == "on" || "$NEW_MODE" == "all") ]]; then
  ANNOUNCE=" IMPORTANT: Begin your next response with '**DUNCE MODE ACTIVATE**' on its own line."
fi

if [[ -n "$REASON" ]]; then
  echo "[SYSTEM: duncemode hook] mode=${NEW_MODE} (was ${CURRENT_MODE}) — ${REASON}. Follow the duncemode skill routing for mode '${NEW_MODE}'.${ANNOUNCE}"
else
  echo "[SYSTEM: duncemode hook] mode=${CURRENT_MODE} (no change)"
fi

exit 0