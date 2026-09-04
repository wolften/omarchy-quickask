# omarchy-quickask

Quick Ask: perguntas rápidas ao agente padrão do Omarchy direto da barra superior.

Clique no ícone para abrir um popup de chat: digite, Enter envia, a resposta transmite em streaming. `+` inicia nova conversa, o outro botão abre o agente no terminal. Respeita `~/.config/omarchy/defaults/agent` (opencode, claude, gemini, codex, crush, copilot, pi, omp, grok).

## Install

```bash
omarchy plugin add https://github.com/wolften/omarchy-quickask --enable
```

Depois adicione à barra (`~/.config/omarchy/shell.json`, seção `right`):

```json
{ "id": "wolften.quickask" }
```

Opcional: atalho `SUPER + SHIFT + A` em `~/.config/hypr/bindings.lua`:

```lua
hl.unbind("SUPER + SHIFT + A")
o.bind("SUPER + SHIFT + A", "Quick Ask", "omarchy-shell shell toggle wolften.quickask")
```

## Tests

```bash
node --test tests/model.test.js
```
