#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
head="$(git -C "$ROOT" rev-parse HEAD)"
base="$(git -C "$ROOT" rev-parse HEAD^)"

decision="$(mktemp)"; result="$(mktemp)"; trap 'rm -f "$decision" "$result"' EXIT
jq -n --arg b "$base" --arg h "$head" '{decision:"SWITCH_ROUTE",audited_base:$b,audited_commit:$h,reason:"test",next_task:"test",batch_limit:3,audit_interval:1,authorized_action:"route_scout",authorized_gap:"K_NEW",superseded_gap:"K_BSP",forbidden_routes:["K_BSP"],reopen_routes:[]}' > "$decision"
jq -e '(.decision=="SWITCH_ROUTE" and .authorized_action=="route_scout")' "$decision" >/dev/null

id="sup-test-authority"
jq -n --arg id "$id" '{parent_decision_id:$id,executed_action:"route_scout",executed_gap:"K_NEW",outcome:"noncounting",summary:"test",commit_message:"research(batch 13): test authorization"}' > "$result"
jq -e --arg id "$id" --arg a "route_scout" --arg g "K_NEW" '.parent_decision_id==$id and .executed_action==$a and .executed_gap==$g' "$result" >/dev/null

[[ "$(jq -r '.routes.K_BSP.status' "$ROOT/control/route_registry.json")" == paused ]]
jq -e '(.forbidden_routes|index("K_BSP"))!=null and (.reopen_routes|index("K_BSP"))==null' "$decision" >/dev/null
echo "PASS: authorization binding and paused-route gate"
