#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_id="hollomancer.agents"
plugin_dir="$HOME/.config/omarchy/plugins/$plugin_id"
shell_json="$HOME/.config/omarchy/shell.json"

mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user" "$HOME/.config/omarchy/plugins"

# ---- collectors + launcher -------------------------------------------------

install -m 0755 "$repo_dir/bin/omarchy-agent-usage-grok" "$HOME/.local/bin/omarchy-agent-usage-grok"
install -m 0755 "$repo_dir/bin/omarchy-agent-usage-openrouter" "$HOME/.local/bin/omarchy-agent-usage-openrouter"
install -m 0755 "$repo_dir/bin/omarchy-agent-launch-openrouter" "$HOME/.local/bin/omarchy-agent-launch-openrouter"

for name in grok openrouter; do
  install -m 0644 "$repo_dir/systemd/omarchy-agent-usage-$name.service" "$HOME/.config/systemd/user/omarchy-agent-usage-$name.service"
  install -m 0644 "$repo_dir/systemd/omarchy-agent-usage-$name.timer" "$HOME/.config/systemd/user/omarchy-agent-usage-$name.timer"
done

systemctl --user daemon-reload
systemctl --user enable --now omarchy-agent-usage-grok.timer omarchy-agent-usage-openrouter.timer
systemctl --user start omarchy-agent-usage-grok.service omarchy-agent-usage-openrouter.service

# ---- agents panel plugin (OpenRouter balance + model picker) --------------
#
# This is a clone of Omarchy's built-in omarchy.agents bar widget, not a
# fresh plugin: the `omarchy.*` id namespace is reserved for first-party
# plugins (the runtime silently drops anything else claiming it), so the
# clone must carry a different id - hence "hollomancer.agents" rather than
# reusing "omarchy.agents". `omarchy plugin clone omarchy.agents` does NOT
# rename the id for you; skipping that rename is what makes the registry
# reject the clone and silently keep running the unmodified original.

mkdir -p "$plugin_dir"
cp -a "$repo_dir/plugin/$plugin_id/." "$plugin_dir/"

python3 - "$shell_json" "$plugin_id" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
plugin_id = sys.argv[2]

data = json.loads(path.read_text()) if path.exists() else {"version": 1, "bar": {"layout": {"right": []}}}
right = data.setdefault("bar", {}).setdefault("layout", {}).setdefault("right", [])

if any(e.get("id") == plugin_id for e in right):
    pass
elif any(e.get("id") == "omarchy.agents" for e in right):
    for e in right:
        if e.get("id") == "omarchy.agents":
            e["id"] = plugin_id
else:
    right.append({"id": plugin_id})

path.write_text(json.dumps(data, indent=2) + "\n")
PY

echo "Installed."
echo "Run 'omarchy restart shell' to load the OpenRouter-enabled agents panel."
echo "Set OPENROUTER_API_KEY (systemd --user environment, or ~/.config/environment.d/)"
echo "for the OpenRouter tab to show a balance; it also needs opencode installed"
echo "and 'opencode providers login -p openrouter' run once to launch a picked model."
