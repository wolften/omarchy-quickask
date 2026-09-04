#!/bin/bash
# wolften.quickask — prints the configured default model for the system's
# default agent, or nothing when unknown/unset. Best-effort per agent.

set -u

agent=""
if command -v omarchy-default-agent >/dev/null 2>&1; then
  agent="$(omarchy-default-agent 2>/dev/null || true)"
fi
[[ -z $agent ]] && exit 0

case "$agent" in
opencode)
  python3 -c 'import json,os
p=os.path.expanduser("~/.config/opencode/opencode.json")
try: print(json.load(open(p)).get("model") or "")
except Exception: print("")' 2>/dev/null
  ;;
codex)
  grep -m1 -E '^[[:space:]]*model[[:space:]]*=' ~/.codex/config.toml 2>/dev/null \
    | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/' || true
  ;;
crush)
  python3 -c 'import json,os
p=os.path.expanduser("~/.config/crush/crush.json")
try: print(json.load(open(p)).get("model") or "")
except Exception: print("")' 2>/dev/null
  ;;
gemini)
  python3 -c 'import json,os
p=os.path.expanduser("~/.muse/settings.json")
try: print(json.load(open(p)).get("model") or "")
except Exception: print("")' 2>/dev/null
  ;;
claude)
  python3 -c 'import json,os
p=os.path.expanduser("~/.claude/settings.json")
try: print(json.load(open(p)).get("model") or "")
except Exception: print("")' 2>/dev/null
  ;;
*)
  exit 0
  ;;
esac
