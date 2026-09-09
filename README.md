# omarchy-agent-widget-extras

Extends Omarchy's `omarchy.agents` bar widget with two things it doesn't
ship out of the box:

- A **Grok CLI** usage tab, alongside the built-in Claude Code / Codex /
  Fireworks tabs.
- A full **OpenRouter** integration: a prepaid-credit balance tab *and* an
  in-panel model picker that launches [opencode](https://opencode.ai)
  against whichever OpenRouter model you select.

## Why this exists as a separate repo

The widget's panel renders whatever usage records it finds in
`~/.local/state/omarchy/agents/usage/*.json` — it doesn't care who wrote
them. But the *automatic* collector dispatcher
(`omarchy-agent-usage-update`) only looks for collectors matching
`$OMARCHY_PATH/bin/omarchy-agent-usage-*`, which is a package-owned path
(`/usr/share/omarchy`) that gets overwritten on every `omarchy update`.
There's no first-party Grok or OpenRouter collector.

So this repo ships its own collectors plus `systemd --user` timers that
write directly to the usage directory the widget watches, entirely outside
Omarchy's package tree.

The OpenRouter model picker needed one more thing the collector approach
can't provide: new UI inside the panel itself. That requires an actual clone
of the `omarchy.agents` plugin (`plugin/hollomancer.agents/`), not just a
data file — see "The reserved-namespace gotcha" below for the one non-obvious
part of doing that.

## What each collector reports

**Grok** reports **local stats** plus a plan tier. Sessions come from
`~/.grok/sessions/**/summary.json` and tokens from the `usage.json` ledger
Grok writes beside each one — the data `grok usage <session-id>` prints —
including the per-model split and a `turns[]` array stamped with end times,
so each day is credited to the turn that earned it. Sessions written before
`usage.json` existed fall back to message counts.

Cached reads are reported as their own bucket rather than folded into input
the way Grok records them, so the panel's input/output/cache hover means the
same thing on the Grok tab as on the Claude and Codex ones.

`tierLabel` comes from the `tier` claim in the stored OIDC token, decoded
locally and never sent anywhere. xAI publishes no mapping from that number to
a plan name, so the collector carries only values confirmed against a real
account — `5` is SuperGrok Heavy. Any other value renders as `Tier N` rather
than guessing at the ladder; name it yourself with `tierLabel` in the config
file below, which overrides both.

Rate-limit windows are still unavailable — xAI exposes no quota endpoint or
RPC, so `limits` stays empty and the panel simply omits that section.

### Cost

Grok records real cost per turn, so the tab shows a **COST** row with what
today cost - no configuration, no API key - and carries the running total on
the line beneath it. Today leads because every other figure on the panel is
today's; a lifetime total only ever grows and says nothing about whether this
session was expensive. Grok is a subscription with no credit ledger to read,
so there is nothing to drain and no meter.

This row also fills the space the **Limits** section occupies on the Claude
and Codex tabs, which stays empty here because xAI exposes no quota endpoint
to read allowance windows from.

Declaring a budget turns that row into the same fuel gauge the prepaid agents
use - funded, remaining, and a bar that drains toward empty - in
`~/.config/omarchy/agents/grok.json`:

```json
{
  "fundedAmount": 20,
  "fundedAt": "2026-09-01",
  "tierLabel": "SuperGrok Heavy"
}
```

`fundedAmount` is your budget for the period starting `fundedAt`; spend
before that date is not charged against it, and the row relabels itself to
say which period it covers. `balanceLabel` renames the row outright. Every
field is optional — with no `fundedAmount` you still get the spend figure,
just no meter to drain.

Grok records cost as an integer `costUsdTicks` and xAI documents the unit
nowhere, so it is read as nanodollars (1e9 ticks = $1). That reading checks
out against published pricing: a recorded session of 13,119 uncached input,
640 cached input and 44 output tokens costs $0.026822 at grok-4.6's list
rates of $2.00 / $0.50 / $6.00 per million, and the ledger recorded
45,597,400 ticks - exactly 1.700000x that, to the tick. A scale of 1.7e9
ticks per dollar would be a strange unit to pick; nanodollars against a
model billed at 1.7x base rates is the reading that makes sense, and the
session ran on `grok-4.6-build` rather than plain `grok-4.6`.

The figure is still labelled **estimated**, because that inference rests on
one session and one model variant. Check it against a real invoice before
trusting it to the cent.

**OpenRouter** is the opposite shape: it's a prepaid-credit router across
many models, not a coding-agent subscription, so there's no local session
history to scan and no plan tier — only a credit balance
(`GET /api/v1/credits`, authenticated with `OPENROUTER_API_KEY`), reported
the same way Omarchy's own Fireworks collector reports its prepaid balance.
The same collector run also refreshes a local cache of OpenRouter's full
model catalog (`GET /api/v1/models`, no auth needed) that the panel's model
picker reads.

Both panels only show a tab once there's something to show:
`providerHasData()` in the widget requires real usage, a balance, or limits
— so the Grok tab appears the first time you've run a real `grok` session,
and the OpenRouter tab appears the first time `OPENROUTER_API_KEY` is set
and the balance fetch succeeds.

## The OpenRouter model picker

On the OpenRouter tab, a filterable list (backed by the cached model
catalog) lets you pick a model. Picking one:

1. Updates the panel immediately (no file round-trip needed for the UI
   itself).
2. Persists the choice to
   `~/.local/state/omarchy/agents/openrouter-selected-model.json`.

Right-clicking the bar icon while the OpenRouter tab is active runs
`omarchy-agent-launch-openrouter`, which reads that file and launches:

```
opencode -m openrouter/<selected-model-id> --auto
```

in a terminal, via the same `omarchy-launch-tui --app-id=org.omarchy.agent`
convention Omarchy's own `omarchy-agent` uses for every other agent. This
needs [opencode](https://opencode.ai) installed and OpenRouter configured as
a provider for it — either `OPENROUTER_API_KEY` in the environment, or
`opencode providers login -p openrouter` run once interactively.

(Omarchy's manual also mentions an `ori` launcher for running other
harnesses against OpenRouter's catalog. It isn't installed or documented
in enough detail — no model-flag syntax, no config path — to build against
reliably, so this repo uses opencode instead: it's actually installed, and
`opencode run --help` / `opencode models` / `opencode providers` document
the exact contract this integration depends on.)

## The reserved-namespace gotcha

If you're adapting this further: `omarchy plugin clone omarchy.agents`
copies the plugin's files but does **not** rename its manifest `id`. The
`omarchy.*` id namespace is reserved for first-party plugins — Quickshell's
`PluginRegistry` silently drops any third-party plugin still claiming an
`omarchy.*` id and keeps running the unmodified original instead, so a clone
left at its default id changes nothing, with no error surfaced anywhere
except a `WARN` line in `~/.local/state/quickshell/.../log.log` reading
`plugin omarchy.agents rejected: id is reserved for first-party Omarchy
plugins`. `plugin/hollomancer.agents/manifest.json` renames the id
(`hollomancer.agents`), and `install.sh` patches `~/.config/omarchy/shell.json`'s
bar layout to point at the renamed id.

## Install

```bash
./install.sh
```

This:
- Installs both collectors and the OpenRouter launcher to `~/.local/bin/`.
- Installs and starts both `systemd --user` timers (15 minute interval,
  matching the widget's default `refreshIntervalSec`).
- Copies `plugin/hollomancer.agents/` into
  `~/.config/omarchy/plugins/hollomancer.agents/`.
- Idempotently repoints `shell.json`'s bar layout from `omarchy.agents` to
  `hollomancer.agents` (or adds it, if the entry is missing entirely).

Then run `omarchy restart shell` to load it — `install.sh` doesn't do this
itself since restarting the bar is disruptive enough that it shouldn't
happen silently as a side effect of a script.

## Verify

```bash
# Run either collector directly and inspect its output
~/.local/bin/omarchy-agent-usage-grok | python3 -m json.tool
~/.local/bin/omarchy-agent-usage-openrouter | python3 -m json.tool

# Force an immediate refresh once installed
systemctl --user start omarchy-agent-usage-grok.service omarchy-agent-usage-openrouter.service
cat ~/.local/state/omarchy/agents/usage/grok.json
cat ~/.local/state/omarchy/agents/usage/openrouter.json

# Ask the widget to re-scan the usage directory right away
omarchy-shell omarchy.agents refresh
```

## Uninstall

```bash
systemctl --user disable --now omarchy-agent-usage-grok.timer omarchy-agent-usage-openrouter.timer
rm -f ~/.config/systemd/user/omarchy-agent-usage-{grok,openrouter}.{service,timer}
rm -f ~/.local/bin/omarchy-agent-usage-grok ~/.local/bin/omarchy-agent-usage-openrouter ~/.local/bin/omarchy-agent-launch-openrouter
rm -f ~/.local/state/omarchy/agents/usage/{grok,openrouter}.json
rm -f ~/.local/state/omarchy/agents/openrouter-selected-model.json
rm -rf ~/.config/omarchy/plugins/hollomancer.agents
systemctl --user daemon-reload
```

Then edit `~/.config/omarchy/shell.json`'s bar layout, change
`hollomancer.agents` back to `omarchy.agents`, and `omarchy restart shell`.

## Known limitations

- **Grok:** no rate-limit windows — `limits` is always empty, since xAI
  exposes no quota endpoint or RPC. `tierLabel` resolves the `tier` claim
  through a small table of confirmed values and otherwise shows `Tier N`;
  name your plan in the config file to override it. Cost is derived
  from `costUsdTicks` on an inferred nanodollar scale and is always flagged
  estimated. Sessions predating Grok's `usage.json` ledger count toward
  prompts and active days with `0` tokens. Requires the `grok` CLI to be on
  `PATH` and signed in.
- **OpenRouter:** no per-model spend breakdown, only the account-wide
  balance — OpenRouter's credits endpoint doesn't split usage by model.
  `tierLabel` reads "Prepaid" (the shape of the account, not a plan), and the
  bundled mark is a routing glyph rather than OpenRouter's brand asset —
  drop a real `assets/openrouter.svg` over it if you have one.
  Requires `OPENROUTER_API_KEY` for the balance tab, and `opencode` (plus
  its own OpenRouter auth) to actually launch a picked model.
- The plugin clone in `plugin/hollomancer.agents/` is a full copy of
  Omarchy's `omarchy.agents` widget at the version it was cloned from. It
  won't pick up upstream improvements to that widget automatically, and a
  future Omarchy update could drift from what this clone assumes about
  `Main.qml`'s data shape.
