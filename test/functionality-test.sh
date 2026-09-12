#!/bin/bash
# Exercises both collectors, their config overrides and edge cases, the
# installed plugin assets, and the systemd units. Run from anywhere.
REPO=/home/omarchy/Projects/omarchy-agent-widget-extras
USAGE=/home/omarchy/.local/state/omarchy/agents/usage
pass=0; fail=0
ck(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; pass=$((pass+1)); else echo "  FAIL  $1 (got '$2' want '$3')"; fail=$((fail+1)); fi; }
ckn(){ if [ -n "$2" ] && [ "$2" != "null" ]; then echo "  PASS  $1 ($2)"; pass=$((pass+1)); else echo "  FAIL  $1 (empty/null)"; fail=$((fail+1)); fi; }

echo "== 1. GROK COLLECTOR =="
out=$("$REPO/bin/omarchy-agent-usage-grok" 2>/dev/null); rc=$?
ck "exits 0" "$rc" "0"
echo "$out" | jq -e . >/dev/null 2>&1 && { echo "  PASS  valid JSON"; pass=$((pass+1)); } || { echo "  FAIL  valid JSON"; fail=$((fail+1)); }

# ground truth from grok's own ledger
gt=$(find /home/omarchy/.grok/sessions -name usage.json 2>/dev/null | xargs -r jq -s '[.[].session]|{tok:(map(.totalTokens)|add),inp:(map(.inputTokens)|add),out:(map(.outputTokens)|add),cr:(map(.cachedReadTokens)|add),ticks:(map(.costUsdTicks)|add),turns:(map(.turnCount)|add)}')
# NOT todayTotalTokens against gt.tok: gt sums the ledger across every day,
# todayTotalTokens is scoped to today, and those only happen to match on the
# day the only real session ran. That coincidence breaks the day after -
# lines 22-23 already validate the lifetime total correctly (modelUsage
# reconstructs gt.tok exactly, with the right scope on both sides).
ck "prompts == turns"     "$(echo "$out"|jq '.totalPrompts')"     "$(echo "$gt"|jq '.turns')"
ck "cost == ticks/1e9"    "$(echo "$out"|jq '.balance.spent')"    "$(echo "$gt"|jq '(.ticks/1e9*1000000|round)/1000000')"
ck "tierLabel"            "$(echo "$out"|jq -r '.tierLabel')"     "SuperGrok Heavy"
# comparability: the three buckets must reconstruct the ledger total
ck "input+output+cache==total" \
  "$(echo "$out"|jq '[.modelUsage[]|.inputTokens+.outputTokens+.cacheReadInputTokens]|add')" "$(echo "$gt"|jq '.tok')"
ck "input is uncached"    "$(echo "$out"|jq '[.modelUsage[].inputTokens]|add')" "$(echo "$gt"|jq '.inp-.cr')"
ck "no budget => funded 0" "$(echo "$out"|jq '.balance.funded==0')" "true"
ck "no budget => label"    "$(echo "$out"|jq -r '.balance.label')" "Spent today"
ckn "recentDays has 7"     "$(echo "$out"|jq '.recentDays|length')"
ck  "recentDays==7"        "$(echo "$out"|jq '.recentDays|length')" "7"

echo "== 2. GROK CONFIG OVERRIDES =="
T=$(mktemp -d); mkdir -p "$T/omarchy/agents"
echo '{"fundedAmount":20,"fundedAt":"2026-09-01","tierLabel":"Custom"}' > "$T/omarchy/agents/grok.json"
b=$(XDG_CONFIG_HOME="$T" "$REPO/bin/omarchy-agent-usage-grok" 2>/dev/null)
ck "budget => funded"      "$(echo "$b"|jq '.balance.funded==20')" "true"
ck "budget => label"       "$(echo "$b"|jq -r '.balance.label')" "Budget remaining"
ck "budget => remaining"   "$(echo "$b"|jq '.balance.remaining < 20 and .balance.remaining > 19')" "true"
ck "tierLabel override"    "$(echo "$b"|jq -r '.tierLabel')" "Custom"
echo '{"fundedAmount":20,"fundedAt":"2030-01-01"}' > "$T/omarchy/agents/grok.json"
ck "future window => 0 spend" "$(XDG_CONFIG_HOME="$T" "$REPO/bin/omarchy-agent-usage-grok" 2>/dev/null|jq '.balance.spent==0')" "true"
rm -rf "$T"

echo "== 3. GROK EDGE CASES =="
E=$(mktemp -d)
o=$(GROK_HOME="$E" "$REPO/bin/omarchy-agent-usage-grok" 2>/dev/null); rc=$?
ck "empty GROK_HOME exits 0" "$rc" "0"
ck "empty => no tokens"      "$(echo "$o"|jq '.todayTotalTokens')" "0"
ck "empty => signed out msg" "$(echo "$o"|jq -r '.authHelpText')" "Run \`grok login\` to authenticate."
ck "empty => no balance"     "$(echo "$o"|jq '.balance')" "null"
# legacy session: summary.json but no usage.json
mkdir -p "$E/sessions/enc/sess1"
printf '{"info":{"id":"s1"},"updated_at":"%s","num_chat_messages":4,"current_model_id":"grok-legacy"}' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$E/sessions/enc/sess1/summary.json"
l=$(GROK_HOME="$E" "$REPO/bin/omarchy-agent-usage-grok" 2>/dev/null)
ck "legacy counts messages"  "$(echo "$l"|jq '.todayTotalTokens')" "4"
ck "legacy model listed"     "$(echo "$l"|jq -r '.modelUsage|keys[0]')" "grok-legacy"
rm -rf "$E"

echo "== 4. OPENROUTER =="
export OPENROUTER_API_KEY=$(sed -n 's/^OPENROUTER_API_KEY=//p' ~/.config/environment.d/openrouter.conf)
o=$("$REPO/bin/omarchy-agent-usage-openrouter" 2>/dev/null); rc=$?
ck "exits 0" "$rc" "0"
ck "tierLabel" "$(echo "$o"|jq -r '.tierLabel')" "Prepaid"
ck "balance not estimated" "$(echo "$o"|jq '.balance.estimated')" "false"
ckn "balance remaining" "$(echo "$o"|jq '.balance.remaining')"
ck "funded>spent consistent" "$(echo "$o"|jq '((.balance.funded - .balance.spent - .balance.remaining)|fabs) < 0.01')" "true"
ckn "model catalog cached" "$(jq 'if type=="array" then length else (.data|length) end' ~/.cache/omarchy/agent-usage/openrouter-models.json 2>/dev/null)"
# Isolated XDG_STATE_HOME: a real persisted selection (the normal state
# after actually using the picker) would otherwise make this actually launch
# a terminal + opencode session and hang the suite instead of failing fast.
L=$(mktemp -d)
XDG_STATE_HOME="$L" "$REPO/bin/omarchy-agent-launch-openrouter" >/dev/null 2>&1; ck "launcher errors w/o selection" "$?" "1"
rm -rf "$L"

echo "== 5. PLUGIN ASSETS =="
A=/home/omarchy/.config/omarchy/plugins/hollomancer.agents/assets
for a in claude codex grok openrouter; do
  [ -f "$A/$a.svg" ] && { echo "  PASS  $a.svg installed"; pass=$((pass+1)); } || { echo "  FAIL  $a.svg missing"; fail=$((fail+1)); }
done
for f in "$A"/*.svg; do python3 -c "import xml.dom.minidom;xml.dom.minidom.parse('$f')" 2>/dev/null || { echo "  FAIL  $f invalid XML"; fail=$((fail+1)); }; done
echo "  PASS  all svgs parse"; pass=$((pass+1))

echo "== 6. SERVICES =="
for u in grok openrouter; do
  ck "$u timer enabled" "$(systemctl --user is-enabled omarchy-agent-usage-$u.timer 2>&1)" "enabled"
  systemctl --user start omarchy-agent-usage-$u.service 2>/dev/null
  ck "$u service ok" "$(systemctl --user show -p ExecMainStatus --value omarchy-agent-usage-$u.service 2>&1)" "0"
done
for a in claude codex grok openrouter; do
  jq -e . "$USAGE/$a.json" >/dev/null 2>&1 && { echo "  PASS  $a.json valid"; pass=$((pass+1)); } || { echo "  FAIL  $a.json invalid"; fail=$((fail+1)); }
done

echo; echo "RESULT: $pass passed, $fail failed"
exit $((fail>0))
