# omarchy-quickask

Quick Ask: a Spotlight-style overlay for one-shot questions to Omarchy's default agent.

The shortcut (or the bar icon) opens a card in the center of the screen with the text field already focused. Type, Enter sends, and the answer streams in. Conversation grows below the input. `+` starts a new chat; the other button opens the agent in a terminal. Esc or a click outside closes it.

Uses `~/.config/omarchy/defaults/agent` (opencode, claude, gemini, codex, crush, copilot, pi, omp, grok).

## Install

```bash
omarchy plugin add https://github.com/wolften/omarchy-quickask --enable
```

Then add it to the bar (`~/.config/omarchy/shell.json`, `right` section):

```json
{ "id": "wolften.quickask" }
```

Optional: `SUPER + SHIFT + A` in `~/.config/hypr/bindings.lua`:

```lua
hl.unbind("SUPER + SHIFT + A")
o.bind("SUPER + SHIFT + A", "Quick Ask", "omarchy-shell shell toggle wolften.quickask")
```

## Tests

```bash
node --test tests/model.test.js
```

## License

MIT. See [LICENSE](LICENSE).
