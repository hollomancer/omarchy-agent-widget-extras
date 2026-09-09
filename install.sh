#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
install -m 0755 "$repo_dir/bin/omarchy-agent-usage-grok" "$HOME/.local/bin/omarchy-agent-usage-grok"
install -m 0644 "$repo_dir/systemd/omarchy-agent-usage-grok.service" "$HOME/.config/systemd/user/omarchy-agent-usage-grok.service"
install -m 0644 "$repo_dir/systemd/omarchy-agent-usage-grok.timer" "$HOME/.config/systemd/user/omarchy-agent-usage-grok.timer"

systemctl --user daemon-reload
systemctl --user enable --now omarchy-agent-usage-grok.timer
systemctl --user start omarchy-agent-usage-grok.service

echo "Installed. Run 'omarchy-shell omarchy.agents refresh' (or open the panel and press r)"
echo "once ~/.local/state/omarchy/agents/usage/grok.json exists to pick it up immediately."
