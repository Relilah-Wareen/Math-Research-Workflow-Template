#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBLEM="$ROOT/notes/problem_statement.md"
REFERENCES="$ROOT/literature/user_references.md"
STATE="$ROOT/iteration_state.json"

for c in git jq sed; do command -v "$c" >/dev/null || { echo "缺少 $c" >&2; exit 1; }; done
[[ -f "$PROBLEM" && -f "$REFERENCES" && -f "$STATE" ]] || { echo "缺少配置文件" >&2; exit 1; }
grep -q '^setup_status: locked$' "$PROBLEM" || { echo "请先填写问题并设置 setup_status: locked" >&2; exit 2; }
if grep -q '\[请填写\]' "$PROBLEM"; then echo "problem_statement.md 仍有 [请填写] 占位项" >&2; exit 2; fi
if grep -q '\[请填写\]' "$REFERENCES"; then echo "user_references.md 仍有 [请填写] 占位项；无参考文献时请明确写“无”" >&2; exit 2; fi

tmp="$(mktemp "$ROOT/.iteration_state.XXXXXX")"
jq '.final_goal_status="open" | .current_gap="K_initial-route-scout:select-first-falsifiable-gate" | .stop_reason="ready_for_bootstrap_supervisor_audit" | .last_iteration_summary="User problem and references locked; no research round has started."' "$STATE" > "$tmp"
mv "$tmp" "$STATE"

git -C "$ROOT" add notes/problem_statement.md literature/user_references.md iteration_state.json
git -C "$ROOT" commit -m "research(batch 0): lock user problem and references"
echo "配置完成。现在运行：./scripts/run_research_supervisor_loop.sh start"
