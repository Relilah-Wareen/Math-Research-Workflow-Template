#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

# Exercise the real orchestrator in disposable repositories; never call a model.
fixture(){
  local root="$1"
  mkdir -p "$root"/{prompts,scripts,control,notes,literature,bin,runs/research_supervisor_loop}
  cp "$PROJECT"/prompts/*.md "$root/prompts/"
  cp "$PROJECT"/scripts/*.schema.json "$root/scripts/"
  cp "$PROJECT/scripts/prepare_project.sh" "$root/scripts/"
  printf 'runs/\nbin/\n' > "$root/.gitignore"
  printf 'setup_status: locked\n' > "$root/notes/problem_statement.md"
  printf '无\n' > "$root/literature/user_references.md"
  printf '{"version":1,"routes":{}}\n' > "$root/control/route_registry.json"
  if [[ "$CASE" == paused || "$CASE" == reopen ]]; then
    printf '{"version":1,"routes":{"K_TEST":{"status":"paused"}}}\n' > "$root/control/route_registry.json"
  fi
  printf '{"batch_id":1,"batch_limit":2,"completed_iterations":0,"total_iterations":0,"final_goal_status":"open","current_gap":"K_TEST","last_iteration_summary":"","stop_reason":""}\n' > "$root/iteration_state.json"
  printf '# log\n' > "$root/work_log.md"
  git -C "$root" init -q
  git -C "$root" config user.name test
  git -C "$root" config user.email test@example.invalid
  git -C "$root" add .
  git -C "$root" commit -qm fixture
  printf '\nbootstrap\n' >> "$root/work_log.md"
  git -C "$root" add work_log.md
  git -C "$root" commit -qm bootstrap
  cat > "$root/bin/codex" <<'FAKE'
#!/usr/bin/env bash
set -Eeuo pipefail
root=""; final=""; schema=""; model=""; sandbox=""
while (($#)); do
  case "$1" in
    -C) root="$2"; shift 2;;
    --output-last-message) final="$2"; shift 2;;
    --output-schema) schema="$2"; shift 2;;
    --model) model="$2"; shift 2;;
    --sandbox) sandbox="$2"; shift 2;;
    *) shift;;
  esac
done
[[ "$model" == fixture-model ]]
prompt="$(cat)"
head="$(git -C "$root" rev-parse HEAD)"; base="$(git -C "$root" rev-parse HEAD^)"
if [[ "$schema" == *supervisor_decision* ]]; then
  [[ "$sandbox" == read-only ]]
  if [[ "$CASE" == retry && ! -f "$root/runs/failed_once" ]]; then
    touch "$root/runs/failed_once"
    echo 'Selected model is at capacity' >&2
    echo '{"type":"turn.completed","usage":{"input_tokens":10,"output_tokens":5}}'
    exit 42
  fi
  if [[ "$(git -C "$root" rev-list --count HEAD)" == 2 ]]; then d=CONTINUE; a=counted_round; else d=STOP; a=stop; fi
  forbidden='[]'; reopen='[]'
  [[ "$CASE" == forbidden ]] && forbidden='["K_TEST"]'
  [[ "$CASE" == reopen ]] && reopen='["K_TEST"]'
  jq -n --arg d "$d" --arg a "$a" --arg b "$base" --arg h "$head" --argjson f "$forbidden" --argjson r "$reopen" \
    '{decision:$d,audited_base:$b,audited_commit:$h,reason:"fixture",next_task:"test",batch_limit:2,audit_interval:1,authorized_action:$a,authorized_gap:"K_TEST",superseded_gap:"",forbidden_routes:$f,reopen_routes:$r}' > "$final"
  [[ "$CASE" == stop_request ]] && touch "$root/runs/research_supervisor_loop/STOP"
else
  printf 'called\n' >> "$root/runs/researcher_calls"
  auth="$(printf '%s\n' "$prompt" | sed -n '/^{/p')"
  id="$(jq -r .decision_id <<< "$auth")"
  if [[ "$CASE" == dirty_retry ]]; then
    printf '\npartial write\n' >> "$root/work_log.md"
    echo 'stream disconnected' >&2
    echo '{"type":"turn.completed","usage":{"input_tokens":10,"output_tokens":5}}'
    exit 42
  fi
  tmp="$root/runs/state.tmp"
  jq '.completed_iterations+=1|.total_iterations+=1|.last_iteration_summary="fixture"' "$root/iteration_state.json" > "$tmp"
  mv "$tmp" "$root/iteration_state.json"
  printf '\nfixture\n' >> "$root/work_log.md"
  jq '.routes.K_NEW={status:"rejected",reason:"fixture",decision_commit:"pending_outer_commit"}' "$root/control/route_registry.json" > "$tmp"
  mv "$tmp" "$root/control/route_registry.json"
  [[ "$CASE" == mismatch ]] && id=wrong-authorization
  jq -n --arg id "$id" '{parent_decision_id:$id,executed_action:"counted_round",executed_gap:"K_TEST",outcome:"success",summary:"fixture",commit_message:"research(batch 1): fixture unit"}' > "$final"
fi
echo '{"type":"turn.completed","usage":{"input_tokens":10,"output_tokens":5}}'
FAKE
  chmod +x "$root/bin/codex"
}

run_loop(){
  PATH="$root/bin:$PATH" RESEARCH_LOOP_ROOT="$root" CODEX_MODEL=fixture-model \
    RESEARCH_LOOP_MAX_RETRIES=1 RESEARCH_LOOP_RETRY_BASE_SECONDS=0 \
    bash "$PROJECT/scripts/run_research_supervisor_loop.sh" "$@"
}

for CASE in success mismatch forbidden paused reopen retry dirty_retry budget stop_request; do
  export CASE
  root="$TEST_ROOT/$CASE"
  fixture "$root"
  budget=0; [[ "$CASE" == budget ]] && budget=15
  if ! run_loop start --max-tokens "$budget" --pause 0 > "$root/runs/test.log" 2>&1; then
    cat "$root/runs/test.log"; exit 1
  fi
  state="$root/runs/research_supervisor_loop/orchestrator_state.json"
  commits="$(git -C "$root" rev-list --count HEAD)"
  case "$CASE" in
    success|reopen|retry)
      [[ "$commits" == 3 && -z "$(git -C "$root" status --porcelain)" ]]
      jq -e '.last_decision=="STOP" and .cycles==1' "$state" >/dev/null
      units=("$root"/runs/research_supervisor_loop/unit_*.json)
      [[ ${#units[@]} == 1 ]]
      jq -e '.authorization.decision_id==.result.parent_decision_id' "${units[0]}" >/dev/null
      ref="$(jq -r .authorization.decision_id "${units[0]}")"
      jq -e --arg ref "authorization:$ref" '.routes.K_NEW.decision_commit==$ref' "$root/control/route_registry.json" >/dev/null
      expected=45; [[ "$CASE" == retry ]] && expected=60
      [[ "$(jq -r .total_tokens "$state")" == "$expected" ]]
      # STOP must survive resume, including any pending user stop request.
      touch "$root/runs/research_supervisor_loop/STOP"
      before="$(sha256sum "$state")"
      rc=0; run_loop resume > "$root/runs/resume.log" 2>&1 || rc=$?
      [[ "$rc" == 4 && "$(sha256sum "$state")" == "$before" ]]
      [[ -f "$root/runs/research_supervisor_loop/STOP" ]]
      ;;
    mismatch|dirty_retry)
      [[ "$commits" == 2 && -n "$(git -C "$root" status --porcelain)" ]]
      [[ "$(wc -l < "$root/runs/researcher_calls")" == 1 ]]
      [[ "$(jq -r .cycles "$state")" == 0 ]]
      ;;
    forbidden|paused|budget|stop_request)
      [[ "$commits" == 2 && ! -e "$root/runs/researcher_calls" ]]
      [[ -z "$(git -C "$root" status --porcelain)" ]]
      ;;
  esac
  echo "PASS: $CASE"
done

# Setup must stop before any agent is invoked, including verbose placeholders.
CASE=setup; export CASE
root="$TEST_ROOT/setup"; fixture "$root"
printf 'setup_status: empty\n' > "$root/notes/problem_statement.md"
rc=0; run_loop start > "$root/runs/setup.log" 2>&1 || rc=$?
[[ "$rc" == 2 && ! -e "$root/runs/research_supervisor_loop/orchestrator_state.json" ]]
printf 'setup_status: locked\n[请填写研究对象。]\n' > "$root/notes/problem_statement.md"
rc=0; bash "$root/scripts/prepare_project.sh" > "$root/runs/prepare.log" 2>&1 || rc=$?
[[ "$rc" == 2 && "$(git -C "$root" rev-list --count HEAD)" == 2 ]]
rc=0; run_loop start > "$root/runs/setup.log" 2>&1 || rc=$?
[[ "$rc" == 2 && ! -e "$root/runs/research_supervisor_loop/orchestrator_state.json" ]]
echo 'PASS: setup lock and placeholders'

# A locked proposition alone is enough: no user bibliography is required.
printf 'setup_status: locked\n# Fixture proposition\n' > "$root/notes/problem_statement.md"
git -C "$root" rm -q literature/user_references.md
bash "$root/scripts/prepare_project.sh" > "$root/runs/prepare.log" 2>&1
[[ "$(git -C "$root" rev-list --count HEAD)" == 3 ]]
jq -e '.final_goal_status=="open"' "$root/iteration_state.json" >/dev/null
run_loop start --max-tokens 15 --pause 0 > "$root/runs/setup.log" 2>&1
jq -e '.supervisor_runs==1' "$root/runs/research_supervisor_loop/orchestrator_state.json" >/dev/null
echo 'PASS: proposition without user references'
