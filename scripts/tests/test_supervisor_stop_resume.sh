#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/prompts" "$TEST_ROOT/scripts" "$TEST_ROOT/runs/research_supervisor_loop"
cp "$PROJECT_ROOT/prompts/07_automated_researcher.md" "$TEST_ROOT/prompts/"
cp "$PROJECT_ROOT/prompts/08_automated_supervisor.md" "$TEST_ROOT/prompts/"
cp "$PROJECT_ROOT/scripts/supervisor_decision.schema.json" "$TEST_ROOT/scripts/"
cp "$PROJECT_ROOT/scripts/researcher_result.schema.json" "$TEST_ROOT/scripts/"
mkdir -p "$TEST_ROOT/control"
cp "$PROJECT_ROOT/control/route_registry.json" "$TEST_ROOT/control/"
git -C "$TEST_ROOT" init -q
git -C "$TEST_ROOT" config user.name test
git -C "$TEST_ROOT" config user.email test@example.invalid
git -C "$TEST_ROOT" add prompts scripts control
git -C "$TEST_ROOT" commit -qm fixture

STATE="$TEST_ROOT/runs/research_supervisor_loop/orchestrator_state.json"
jq -n '{
  version:3,status:"stopped",phase:"supervisor",cycles:1,researcher_runs:0,supervisor_runs:1,
  researcher_tokens:0,supervisor_tokens:1,total_tokens:1,current_head:"fixture",
  last_audited_commit:"fixture",last_decision:"STOP",last_reason:"audit stop",next_task:"",
  audit_interval:1,unaudited_count:0,max_tokens:0,started_at:"fixture",updated_at:"fixture"
}' > "$STATE"
before="$(sha256sum "$STATE" | awk '{print $1}')"

set +e
output="$(RESEARCH_LOOP_ROOT="$TEST_ROOT" "$PROJECT_ROOT/scripts/run_research_supervisor_loop.sh" resume 2>&1)"
rc=$?
set -e

[[ "$rc" -eq 4 ]] || { echo "expected resume refusal rc=4, got $rc" >&2; exit 1; }
[[ "$output" == *"上次决定 STOP；请使用 start 重新审核"* ]] || { echo "missing STOP refusal" >&2; exit 1; }
[[ "$(sha256sum "$STATE" | awk '{print $1}')" == "$before" ]] || { echo "STOP state changed during resume" >&2; exit 1; }
[[ "$(jq -r '.status + ":" + .phase + ":" + .last_decision' "$STATE")" == "stopped:supervisor:STOP" ]] || {
  echo "STOP audit gate was not preserved" >&2
  exit 1
}

echo "PASS: Supervisor STOP blocks resume and preserves the audit gate"
