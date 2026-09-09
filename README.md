# omarchy-grok-agent-widget

Adds a Grok CLI tab to Omarchy's `omarchy.agents` bar widget, alongside the
built-in Claude Code / Codex / Fireworks tabs.

## Why this exists as a separate repo

The widget's panel renders whatever usage records it finds in
`~/.local/state/omarchy/agents/usage/*.json` — it doesn't care who wrote
them. But the *automatic* collector dispatcher
(`omarchy-agent-usage-update`) only looks for collectors matching
`$OMARCHY_PATH/bin/omarchy-agent-usage-*`, which is a package-owned path
(`/usr/share/omarchy`) that gets overwritten on every `omarchy update`.
There's no first-party Grok collector and no user-level override directory
for this kind of script (unlike shell plugins, which clone into
`~/.config/omarchy/plugins/`).

So this repo ships its own collector plus a `systemd --user` timer that
writes directly to the usage directory the widget watches, entirely outside
Omarchy's package tree. Nothing here touches `/usr/share/omarchy`.

## What it reports

Grok has no documented rate-limit or plan API reachable from the CLI (unlike
Anthropic's OAuth usage endpoint or the Codex app-server RPC), so this only
ever reports **local stats**: sessions and messages found under
`~/.grok/sessions/**/summary.json`, with token counts from `signals.json`
when that file has a recognizable shape (its schema isn't publicly
documented, so it's parsed defensively and falls back to message counts).

The panel only shows a tab once a subscription has recorded actual usage, so
the Grok tab appears the first time you've run a real `grok` session and the
timer has fired (or you've forced a refresh — see below).

## Install

```bash
./install.sh
```

This copies `bin/omarchy-agent-usage-grok` to `~/.local/bin/`, installs a
`systemd --user` service + timer (15 minute interval, matching the widget's
default `refreshIntervalSec`), and starts both.

## Verify

```bash
# Run the collector directly and inspect its output
~/.local/bin/omarchy-agent-usage-grok | python3 -m json.tool

# Force an immediate refresh once installed
systemctl --user start omarchy-agent-usage-grok.service
cat ~/.local/state/omarchy/agents/usage/grok.json

# Ask the widget to re-scan the usage directory right away
omarchy-shell omarchy.agents refresh
```

## Uninstall

```bash
systemctl --user disable --now omarchy-agent-usage-grok.timer
rm -f ~/.config/systemd/user/omarchy-agent-usage-grok.{service,timer}
rm -f ~/.local/bin/omarchy-agent-usage-grok
rm -f ~/.local/state/omarchy/agents/usage/grok.json
systemctl --user daemon-reload
```

## Known limitations

- No rate-limit / plan-tier data — `limits` is always empty and `tierLabel`
  is always blank, since there's no API to query for it.
- Token counts depend on `signals.json`'s undocumented shape; if none of the
  field names the script tries match, sessions still count toward prompts
  and active days, just with `0` tokens.
- Requires the `grok` CLI to be on `PATH`; without it (or without being
  signed in), the record explains why in `authHelpText` instead of reporting
  stats.
