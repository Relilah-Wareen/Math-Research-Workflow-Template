#!/usr/bin/env bash
set -Eeuo pipefail
P="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T"/{prompts,scripts,control,bin,runs/research_supervisor_loop}
cp "$P"/prompts/0{7,8}_automated_*.md "$T/prompts/"
cp "$P"/scripts/{supervisor_decision,researcher_result}.schema.json "$T/scripts/"
cp "$P/control/route_registry.json" "$T/control/"
printf 'runs/\nbin/\n' > "$T/.gitignore"; printf '{"batch_id":1,"batch_limit":2,"completed_iterations":0,"total_iterations":0,"final_goal_status":"open","current_gap":"K_TEST","last_iteration_summary":"","stop_reason":""}\n' > "$T/iteration_state.json"; printf '# log\n' > "$T/work_log.md"
git -C "$T" init -q; git -C "$T" config user.name test; git -C "$T" config user.email test@example.invalid; git -C "$T" add .; git -C "$T" commit -qm fixture
printf '\nbootstrap\n' >> "$T/work_log.md"; git -C "$T" add work_log.md; git -C "$T" commit -qm bootstrap

cat > "$T/bin/codex" <<'FAKE'
#!/usr/bin/env bash
set -Eeuo pipefail
root=""; final=""; schema=""; while (($#)); do case "$1" in -C) root="$2"; shift 2;; --output-last-message) final="$2"; shift 2;; --output-schema) schema="$2"; shift 2;; *) shift;; esac; done
prompt="$(mktemp)"; cat > "$prompt"; head="$(git -C "$root" rev-parse HEAD)"; base="$(git -C "$root" rev-parse HEAD^)"
if [[ "$schema" == *supervisor_decision* ]]; then
  if [[ "$(git -C "$root" rev-list --count HEAD)" == 2 ]]; then d=CONTINUE; a=counted_round; task=test; else d=STOP; a=stop; task=""; fi
  jq -n --arg d "$d" --arg a "$a" --arg b "$base" --arg h "$head" --arg task "$task" '{decision:$d,audited_base:$b,audited_commit:$h,reason:"fixture",next_task:$task,batch_limit:2,audit_interval:1,authorized_action:$a,authorized_gap:"K_TEST",superseded_gap:"",forbidden_routes:[],reopen_routes:[]}' > "$final"
else
  auth="$(grep '^{' "$prompt" | tail -1)"; id="$(jq -r .decision_id <<<"$auth")"
  tmp="$(mktemp)"; jq '.completed_iterations+=1|.total_iterations+=1|.last_iteration_summary="fixture success"' "$root/iteration_state.json" > "$tmp"; mv "$tmp" "$root/iteration_state.json"; printf '\nfixture\n' >> "$root/work_log.md"
  tmp_route="$(mktemp)"; jq '.routes.K_NEW={status:"rejected",reason:"fixture",decision_commit:"pending_outer_commit"}' "$root/control/route_registry.json" > "$tmp_route"; mv "$tmp_route" "$root/control/route_registry.json"
  jq -n --arg id "$id" '{parent_decision_id:$id,executed_action:"counted_round",executed_gap:"K_TEST",outcome:"success",summary:"fixture",commit_message:"research(batch 1): fixture unit"}' > "$final"
fi
echo '{"type":"turn.completed","usage":{"input_tokens":10,"output_tokens":5}}'; rm -f "$prompt"
FAKE
chmod +x "$T/bin/codex"
PATH="$T/bin:$PATH" RESEARCH_LOOP_ROOT="$T" "$P/scripts/run_research_supervisor_loop.sh" start --max-tokens 0 --pause 0 >/dev/null
[[ "$(git -C "$T" rev-list --count HEAD)" == 3 ]]; [[ -z "$(git -C "$T" status --porcelain)" ]]; [[ "$(jq -r .last_decision "$T/runs/research_supervisor_loop/orchestrator_state.json")" == STOP ]];
u="$(find "$T/runs/research_supervisor_loop" -name 'unit_*.json' -type f | head -1)"; [[ -n "$u" ]]; jq -e '.authorization.decision_id==.result.parent_decision_id' "$u" >/dev/null
ref="$(jq -r .authorization.decision_id "$u")"; jq -e --arg ref "authorization:$ref" '.routes.K_NEW.decision_commit==$ref' "$T/control/route_registry.json" >/dev/null
echo 'PASS: script-owned commit and authorization audit loop'
