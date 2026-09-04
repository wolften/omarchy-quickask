#!/bin/bash
# wolften.quickask — one-shot dispatcher for the system's default agent.
# Reads ~/.config/omarchy/defaults/agent via `omarchy-default-agent` and runs
# the matching agent in non-interactive (headless) mode so a bar popup can
# capture the answer on stdout.
#
# Usage: ask.sh "<question>" [--dir <path>]
# Exit 0 on answer printed to stdout; non-zero with error on stderr.

set -u

# The bar spawns us with a pipe on stdin whose write end stays open, which
# makes agent CLIs that probe stdin (notably `opencode run`) block forever
# waiting for input/EOF. Detach stdin so children always see EOF instead.
exec </dev/null

question="${1:-}"
if [[ -z $question ]]; then
  echo "ask.sh: empty question" >&2
  exit 2
fi

workdir="$HOME/Work"
if [[ ${2:-} == "--dir" && -n ${3:-} ]]; then
  workdir="$3"
fi
[[ -d $workdir ]] || workdir="$HOME"
cd "$workdir" || exit 2

agent=""
if command -v omarchy-default-agent >/dev/null 2>&1; then
  agent="$(omarchy-default-agent 2>/dev/null || true)"
fi
if [[ -z $agent ]]; then
  echo "Nenhum agente padrão configurado. Rode: omarchy default agent <name>" >&2
  exit 3
fi

if ! command -v "$agent" >/dev/null 2>&1; then
  echo "$agent is not installed. Choose an installed agent with: omarchy default agent <name>" >&2
  exit 3
fi

case "$agent" in
opencode)
  # quickask agent (~/.config/opencode/agents/quickask.md): read-only
  # (edit/bash/task denied), scoped to these runs only.
  exec opencode run --agent quickask "$question"
  ;;
crush)
  exec crush run "$question"
  ;;
claude)
  # -p = print mode (non-interactive)
  exec claude -p "$question"
  ;;
codex)
  exec codex exec "$question"
  ;;
gemini)
  exec gemini -p "$question"
  ;;
copilot)
  exec copilot -p "$question"
  ;;
grok)
  exec grok -p "$question"
  ;;
pi)
  exec pi --print "$question"
  ;;
omp)
  exec omp --print "$question"
  ;;
*)
  echo "Unsupported default agent: $agent" >&2
  exit 3
  ;;
esac
