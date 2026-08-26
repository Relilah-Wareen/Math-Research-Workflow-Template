#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${RESEARCH_LOOP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
RUN_ROOT="$ROOT/runs/research_supervisor_loop"; STATE="$RUN_ROOT/orchestrator_state.json"; STOP_FILE="$RUN_ROOT/STOP"
SUP_PROMPT="$ROOT/prompts/08_automated_supervisor.md"; RES_PROMPT="$ROOT/prompts/07_automated_researcher.md"
SUP_SCHEMA="$ROOT/scripts/supervisor_decision.schema.json"; RES_SCHEMA="$ROOT/scripts/researcher_result.schema.json"
REGISTRY="$ROOT/control/route_registry.json"; AUTH="$RUN_ROOT/current_authorization.json"
MAX_TOKENS=0; PAUSE_SECONDS=2; active_pid=""

usage(){ echo "用法: $0 start|resume|status [--max-tokens N] [--pause N]"; }
for c in codex jq git sed tee awk sha256sum; do command -v "$c" >/dev/null || { echo "缺少 $c" >&2; exit 1; }; done
mode="${1:-}"; shift || true
while (($#)); do case "$1" in --max-tokens) MAX_TOKENS="${2:-}"; shift 2;; --pause) PAUSE_SECONDS="${2:-}"; shift 2;; *) usage; exit 2;; esac; done
[[ "$MAX_TOKENS" =~ ^[0-9]+$ && "$PAUSE_SECONDS" =~ ^[0-9]+$ ]] || exit 2
mkdir -p "$RUN_ROOT"
if [[ "$mode" == status ]]; then [[ -f "$STATE" ]] && jq . "$STATE" || echo "尚无状态"; [[ -e "$STOP_FILE" ]] && echo "安全停止请求：已设置" || echo "安全停止请求：未设置"; exit 0; fi
[[ "$mode" == start || "$mode" == resume ]] || { usage; exit 2; }
[[ -f "$SUP_PROMPT" && -f "$RES_PROMPT" && -f "$SUP_SCHEMA" && -f "$RES_SCHEMA" && -f "$REGISTRY" ]] || { echo "缺少协议文件" >&2; exit 2; }
rm -f "$STOP_FILE"
if [[ "$mode" == start ]]; then
  [[ -z "$(git -C "$ROOT" status --porcelain)" ]] || { echo "工作树不干净；拒绝启动" >&2; git -C "$ROOT" status --short >&2; exit 3; }
  head="$(git -C "$ROOT" rev-parse HEAD)"; base="$(git -C "$ROOT" rev-parse HEAD^)"
  jq -n --arg h "$head" --arg b "$base" --argjson m "$MAX_TOKENS" '{version:3,status:"running",phase:"supervisor",cycles:0,researcher_runs:0,supervisor_runs:0,researcher_tokens:0,supervisor_tokens:0,total_tokens:0,current_head:$h,last_audited_commit:$b,last_decision:"",last_reason:"",current_decision_id:"",audit_interval:1,unaudited_count:1,max_tokens:$m,started_at:(now|todate),updated_at:(now|todate)}' > "$STATE"
else
  [[ -f "$STATE" ]] || { echo "没有状态" >&2; exit 3; }
  [[ "$(jq -r '.last_decision//""' "$STATE")" != STOP ]] || { echo "上次决定 STOP；请使用 start 重新审核" >&2; exit 4; }
  [[ -z "$(git -C "$ROOT" status --porcelain)" ]] || { echo "工作树不干净；拒绝恢复" >&2; git -C "$ROOT" status --short >&2; exit 3; }
  tmp="$(mktemp "$RUN_ROOT/.state.XXXX")"; jq --argjson m "$MAX_TOKENS" '.version=3|.status="running"|.max_tokens=$m|.updated_at=(now|todate)' "$STATE" > "$tmp"; mv "$tmp" "$STATE"
fi

on_interrupt(){ [[ -n "$active_pid" ]] && kill -INT "$active_pid" 2>/dev/null || true; tmp="$(mktemp "$RUN_ROOT/.state.XXXX")"; jq '.status="interrupted"' "$STATE" > "$tmp" && mv "$tmp" "$STATE"; exit 130; }
trap on_interrupt INT TERM
tokens(){ jq -s '[.[]|select(.type=="turn.completed")|.usage|((.input_tokens//0)+(.output_tokens//0))]|add//0' "$1" 2>/dev/null || echo 0; }
usage_add(){ local role="$1" n="$2" t="$(mktemp "$RUN_ROOT/.state.XXXX")"; if [[ "$role" == supervisor ]]; then jq --argjson n "$n" '.supervisor_runs+=1|.supervisor_tokens+=$n|.total_tokens+=$n' "$STATE" > "$t"; else jq --argjson n "$n" '.researcher_runs+=1|.researcher_tokens+=$n|.total_tokens+=$n' "$STATE" > "$t"; fi; mv "$t" "$STATE"; }
stop_gate(){ [[ -e "$STOP_FILE" ]] && return 0; local u="$(jq -r .total_tokens "$STATE")" m="$(jq -r .max_tokens "$STATE")"; ((m>0&&u>=m)); }
run(){ local role="$1" prompt="$2" log="$3" final="$4" schema="$5"; local -a a=(exec --skip-git-repo-check -C "$ROOT" --json --output-last-message "$final" --output-schema "$schema"); [[ "$role" == supervisor ]] && a+=(--sandbox read-only) || a+=(--approve-for-me); set +e; codex "${a[@]}" - < "$prompt" > >(tee "$log") 2> >(tee "${log%.jsonl}.stderr.log" >&2) & active_pid=$!; wait "$active_pid"; rc=$?; active_pid=""; set -e; return "$rc"; }
action_ok(){ case "$1:$2" in CONTINUE:counted_round|REPAIR:repair|SWITCH_ROUTE:route_scout|NEW_BATCH:new_batch|STOP:stop) return 0;; *) return 1;; esac; }

while true; do
  stop_gate && break
  phase="$(jq -r .phase "$STATE")"; head="$(git -C "$ROOT" rev-parse HEAD)"; stamp="$(date +%Y%m%d_%H%M%S)"
  if [[ "$phase" == supervisor ]]; then
    base="$(jq -r .last_audited_commit "$STATE")"; git -C "$ROOT" merge-base --is-ancestor "$base" "$head" || { echo "审核基点错误" >&2; break; }
    p="$RUN_ROOT/supervisor_$stamp.md"; l="$RUN_ROOT/supervisor_$stamp.jsonl"; f="$RUN_ROOT/supervisor_${stamp}_decision.json"
    sed -e "s/{{AUDIT_BASE}}/$base/g" -e "s/{{AUDIT_COMMIT}}/$head/g" "$SUP_PROMPT" > "$p"
    run supervisor "$p" "$l" "$f" "$SUP_SCHEMA" || { echo "Supervisor 失败" >&2; break; }; usage_add supervisor "$(tokens "$l")"
    jq -e --arg b "$base" --arg h "$head" '.audited_base==$b and .audited_commit==$h and (.reason|length)>0 and (.batch_limit>=2 and .batch_limit<=8) and (.audit_interval>=1 and .audit_interval<=3)' "$f" >/dev/null || { echo "审核输出哈希不符" >&2; break; }
    decision="$(jq -r .decision "$f")"; action="$(jq -r .authorized_action "$f")"; action_ok "$decision" "$action" || { echo "决定与动作不一致" >&2; break; }
    decision_id="sup-$(sha256sum "$f"|awk '{print substr($1,1,20)}')"
    jq --arg id "$decision_id" '.+{decision_id:$id}' "$f" > "$AUTH"
    tmp="$(mktemp "$RUN_ROOT/.state.XXXX")"; jq --arg d "$decision" --arg r "$(jq -r .reason "$f")" --arg id "$decision_id" --arg h "$head" --argjson ai "$(jq -r .audit_interval "$f")" '.last_decision=$d|.last_reason=$r|.current_decision_id=$id|.last_audited_commit=$h|.audit_interval=$ai|.unaudited_count=0|.phase=(if $d=="STOP" then "supervisor" else "researcher" end)|.status=(if $d=="STOP" then "stopped" else .status end)' "$STATE" > "$tmp"; mv "$tmp" "$STATE"
    [[ "$decision" == STOP ]] && break
  else
    [[ -f "$AUTH" ]] || { echo "缺少唯一授权文件" >&2; break; }
    decision="$(jq -r .decision "$AUTH")"; action="$(jq -r .authorized_action "$AUTH")"; decision_id="$(jq -r .decision_id "$AUTH")"
  fi
  stop_gate && break

  p="$RUN_ROOT/researcher_$stamp.md"; l="$RUN_ROOT/researcher_$stamp.jsonl"; f="$RUN_ROOT/researcher_${stamp}_result.json"
  auth_compact="$(jq -c . "$AUTH")"; awk -v a="$auth_compact" '{if($0=="{{AUTHORIZATION_JSON}}")print a;else print}' "$RES_PROMPT" > "$p"
  before_head="$head"; bc="$(jq -r .completed_iterations iteration_state.json)"; bt="$(jq -r .total_iterations iteration_state.json)"; bb="$(jq -r .batch_id iteration_state.json)"
  run researcher "$p" "$l" "$f" "$RES_SCHEMA" || { echo "Researcher 失败" >&2; break; }; usage_add researcher "$(tokens "$l")"
  [[ "$(git -C "$ROOT" rev-parse HEAD)" == "$before_head" ]] || { echo "Researcher 禁止自行提交" >&2; break; }
  [[ -n "$(git -C "$ROOT" status --porcelain)" ]] || { echo "Researcher 未产生修改" >&2; break; }
  jq -e --arg id "$decision_id" --arg a "$action" --arg g "$(jq -r .authorized_gap "$AUTH")" '.parent_decision_id==$id and (.parent_decision_id|length)>=8 and .executed_action==$a and .executed_gap==$g and (.executed_gap|length)>0 and (.summary|length)>0 and (.commit_message|test("^research\\(batch [0-9]+\\): [^\\n]+$"))' "$f" >/dev/null || { echo "执行 manifest 与授权不符" >&2; break; }
  gap="$(jq -r .executed_gap "$f")"; jq -e --arg g "$gap" '(.forbidden_routes|index($g))==null' "$AUTH" >/dev/null || { echo "执行了禁止路线 $gap" >&2; break; }
  route_status="$(jq -r --arg g "$gap" '.routes[$g].status // "unknown"' "$REGISTRY")"; if [[ "$route_status" == paused || "$route_status" == rejected ]]; then jq -e --arg g "$gap" '(.reopen_routes|index($g))!=null' "$AUTH" >/dev/null || { echo "路线 $gap 状态为 $route_status 且未显式重开" >&2; break; }; fi
  if grep -q '"decision_commit": "pending_outer_commit"' "$REGISTRY"; then tmp_registry="$(mktemp "$RUN_ROOT/.registry.XXXX")"; jq --arg ref "authorization:$decision_id" '(.routes[] | select(.decision_commit == "pending_outer_commit").decision_commit) = $ref' "$REGISTRY" > "$tmp_registry"; mv "$tmp_registry" "$REGISTRY"; fi
  git -C "$ROOT" diff --check; git -C "$ROOT" add -A
  forbidden="$(git -C "$ROOT" diff --cached --name-only | grep -E '(^|/)(\.env|id_rsa|credentials|secrets?)(\.|/|$)|^runs/|^papers/' || true)"
  [[ -z "$forbidden" ]] || { echo "禁止提交文件: $forbidden" >&2; git -C "$ROOT" restore --staged .; break; }
  msg="$(jq -r .commit_message "$f")"; git -C "$ROOT" diff --cached --quiet && { echo "无 staged 修改" >&2; break; }
  git -C "$ROOT" commit -m "$msg"; after_head="$(git -C "$ROOT" rev-parse HEAD)"; [[ -z "$(git -C "$ROOT" status --porcelain)" ]] || { echo "提交后工作树不净" >&2; break; }
  jq -n --arg commit "$after_head" --slurpfile authorization "$AUTH" --slurpfile result "$f" '{commit:$commit,authorization:$authorization[0],result:$result[0]}' > "$RUN_ROOT/unit_${after_head}.json"

  ac="$(jq -r .completed_iterations iteration_state.json)"; at="$(jq -r .total_iterations iteration_state.json)"; ab="$(jq -r .batch_id iteration_state.json)"; al="$(jq -r .batch_limit iteration_state.json)"; fs="$(jq -r .final_goal_status iteration_state.json)"
  dc=$((ac-bc)); dt=$((at-bt)); u=$(( $(jq -r .unaudited_count "$STATE") + 1 )); ai="$(jq -r .audit_interval "$STATE")"; immediate=false
  [[ "$action" != counted_round ]] && immediate=true; ((dc!=1||dt!=1||ab!=bb||ac>=al||u>=ai)) && immediate=true; [[ "$fs" != open ]] && immediate=true
  if [[ "$immediate" == true ]]; then np=supervisor; else
    np=researcher; new_id="auto-$(date +%s)-${after_head:0:8}"; jq -n --arg id "$new_id" --arg gap "$(jq -r .current_gap iteration_state.json)" --argjson bl "$al" --argjson ai "$ai" --argjson forbidden "$(jq .forbidden_routes "$AUTH")" '{decision_id:$id,decision:"AUTO_CONTINUE",authorized_action:"counted_round",authorized_gap:$gap,superseded_gap:"",reopen_routes:[],forbidden_routes:$forbidden,next_task:"Execute exactly one falsifiable counted unit from current_gap",batch_limit:$bl,audit_interval:$ai}' > "$AUTH"
  fi
  tmp="$(mktemp "$RUN_ROOT/.state.XXXX")"; jq --arg h "$after_head" --arg p "$np" --argjson u "$u" '.cycles+=1|.current_head=$h|.phase=$p|.unaudited_count=$u|.updated_at=(now|todate)' "$STATE" > "$tmp"; mv "$tmp" "$STATE"
  sleep "$PAUSE_SECONDS"
done
tmp="$(mktemp "$RUN_ROOT/.state.XXXX")"; jq '.status="stopped"|.updated_at=(now|todate)' "$STATE" > "$tmp" && mv "$tmp" "$STATE"; jq . "$STATE"
