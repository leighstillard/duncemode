#!/usr/bin/env bash
# install.sh — install the duncemode skill hook for Claude Code.
#
# Idempotent. Safe to run repeatedly. Makes a timestamped backup of
# settings.json every time it modifies it.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_REL="hooks/duncemode-detect.sh"
HOOK_PATH="$SKILL_DIR/$HOOK_REL"
SETTINGS_DIR="$HOME/.claude"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
STATE_DIR="$HOME/.claude/state"

say()  { printf '  %s\n' "$*"; }
ok()   { printf '  \033[32m[OK]\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m[!!]\033[0m %s\n' "$*" >&2; }
info() { printf '  \033[36m[..]\033[0m %s\n' "$*"; }

echo
echo "duncemode installer"
echo "==================="
echo

# 1. Check we're running from the skill directory
if [[ ! -f "$HOOK_PATH" ]]; then
  bad "can't find the hook script at $HOOK_PATH"
  bad "run this installer from the duncemode skill directory:"
  bad "  cd path/to/duncemode && ./install.sh"
  exit 1
fi
ok "found hook script at $HOOK_PATH"

# 2. Check jq
if ! command -v jq >/dev/null 2>&1; then
  bad "jq is not installed. duncemode needs jq for JSON parsing."
  echo
  echo "  install it with:"
  echo "    macOS:         brew install jq"
  echo "    Ubuntu/Debian: sudo apt install jq"
  echo "    Arch:          sudo pacman -S jq"
  echo "    Fedora:        sudo dnf install jq"
  echo
  echo "  then re-run this installer."
  exit 1
fi
ok "jq found: $(jq --version)"

# 3. Make the hook executable
chmod +x "$HOOK_PATH"
ok "hook script is executable"

# 4. Create state directory
mkdir -p "$STATE_DIR"
ok "state directory ready at $STATE_DIR"

# 5. Create settings directory
mkdir -p "$SETTINGS_DIR"

# 6. Handle settings.json — create if missing, back up if present
if [[ ! -f "$SETTINGS_FILE" ]]; then
  info "no settings.json found, creating a fresh one"
  echo '{}' > "$SETTINGS_FILE"
  ok "created $SETTINGS_FILE"
else
  # Validate that it's valid JSON before we touch it
  if ! jq empty "$SETTINGS_FILE" >/dev/null 2>&1; then
    bad "$SETTINGS_FILE exists but is not valid JSON. fix it first, then re-run."
    exit 1
  fi
  ok "found existing valid $SETTINGS_FILE"
fi

# 7. Check if the hook is already wired up (by path match)
ALREADY_INSTALLED=$(jq --arg path "$HOOK_PATH" \
  '((.hooks.UserPromptSubmit // []) | map(.args[0]? // "") | index($path)) != null' \
  "$SETTINGS_FILE")

if [[ "$ALREADY_INSTALLED" == "true" ]]; then
  ok "hook already wired up in settings.json — nothing to change"
else
  # 8. Back up settings.json before modifying
  BACKUP_FILE="$SETTINGS_FILE.duncemode-backup.$(date +%Y%m%d-%H%M%S)"
  cp "$SETTINGS_FILE" "$BACKUP_FILE"
  ok "backed up existing settings to $BACKUP_FILE"

  # 9. Merge the new hook entry into settings.json
  info "wiring hook into settings.json"
  TMP_FILE="$(mktemp)"
  jq --arg path "$HOOK_PATH" \
    '.hooks = (.hooks // {}) |
     .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) +
       [{command: "bash", args: [$path]}])' \
    "$SETTINGS_FILE" > "$TMP_FILE"

  # Validate the result is still valid JSON before replacing
  if ! jq empty "$TMP_FILE" >/dev/null 2>&1; then
    bad "merge produced invalid JSON. backup is at $BACKUP_FILE"
    rm -f "$TMP_FILE"
    exit 1
  fi

  mv "$TMP_FILE" "$SETTINGS_FILE"
  ok "hook wired up"
fi

# 10. Smoke test the hook
info "running hook smoke test"
TEST_INPUT='{"user_message":"bullshit, that did not actually run"}'
TEST_OUTPUT="$(echo "$TEST_INPUT" | bash "$HOOK_PATH" 2>&1)" || {
  bad "hook crashed during smoke test:"
  echo "$TEST_OUTPUT" >&2
  exit 1
}

if echo "$TEST_OUTPUT" | grep -q "mode=all"; then
  ok "smoke test passed"
  say "hook output: $TEST_OUTPUT"
else
  bad "smoke test produced unexpected output:"
  echo "$TEST_OUTPUT" >&2
  exit 1
fi

# 11. Reset state file to off (so we don't leave it in "all" after the test)
echo "{\"mode\":\"off\",\"previous_mode\":\"all\",\"last_reason\":\"installer reset\",\"updated_at\":\"$(date -Iseconds)\"}" \
  > "$STATE_DIR/duncemode.json"
ok "state reset to off"

echo
echo "  installation complete."
echo
echo "  to verify in Claude Code, start a new session and say:"
echo "      duncemode status"
echo
echo "  to enable:"
echo "      duncemode on"
echo
echo "  to disable:"
echo "      duncemode off"
echo
echo "  read README.md for tuning, troubleshooting, and unnecessary sarcasm."
echo
