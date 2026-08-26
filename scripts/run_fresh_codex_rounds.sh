#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="$ROOT/iteration_state.json"
PROMPT="$ROOT/prompts/03_single_fresh_round.md"

usage() {
  printf '用法：\n'
  printf '  %s new <轮数> [--auto]   新建一批并逐轮运行\n' "$0"
  printf '  %s resume [--auto]       继续当前未完成批次\n' "$0"
  printf '\n不加 --auto 时，每轮结束后等待 Enter；加上后自动连续运行。\n'
}

[[ -f "$STATE" && -f "$PROMPT" ]] || {
  printf '缺少状态文件或单轮提示词。\n' >&2
  exit 1
}
command -v codex >/dev/null || { printf '未找到 codex 命令。\n' >&2; exit 1; }
command -v jq >/dev/null || { printf '未找到 jq 命令。\n' >&2; exit 1; }

mode="${1:-}"
auto_mode=false
case "$mode" in
  new)
    rounds="${2:-}"
    [[ "$rounds" =~ ^[1-9][0-9]*$ ]] || { usage; exit 2; }
    [[ "${3:-}" == "--auto" || -z "${3:-}" ]] || { usage; exit 2; }
    [[ "${3:-}" == "--auto" ]] && auto_mode=true
    [[ "$(jq -r '.final_goal_status' "$STATE")" == "open" ]] || {
      printf '最终目标已不是 open；拒绝新建批次。\n' >&2
      exit 1
    }
    tmp="$(mktemp "$ROOT/.iteration_state.XXXXXX")"
    jq --argjson limit "$rounds" '
      .batch_id += 1
      | .batch_limit = $limit
      | .completed_iterations = 0
      | .stop_reason = "fresh_process_batch_started"
    ' "$STATE" > "$tmp"
    mv "$tmp" "$STATE"
    ;;
  resume)
    [[ "${2:-}" == "--auto" || -z "${2:-}" ]] || { usage; exit 2; }
    [[ "${2:-}" == "--auto" ]] && auto_mode=true
    ;;
  *)
    usage
    exit 2
    ;;
esac

batch_id="$(jq -r '.batch_id' "$STATE")"
limit="$(jq -r '.batch_limit' "$STATE")"
current_gap="$(jq -r '.current_gap' "$STATE")"

if [[ "$current_gap" == K_new-route-scout:* ]]; then
  printf '当前状态要求先执行不计数的新路线探索，不能启动正式研究轮。\n' >&2
  printf '请运行：codex exec --approve-for-me --skip-git-repo-check -C %q - < %q\n' \
    "$ROOT" "$ROOT/prompts/04_new_route_scout.md" >&2
  exit 5
fi

run_dir="$ROOT/runs/batch_${batch_id}_fresh_processes"
mkdir -p "$run_dir"

while true; do
  status="$(jq -r '.final_goal_status' "$STATE")"
  before="$(jq -r '.completed_iterations' "$STATE")"
  total_before="$(jq -r '.total_iterations' "$STATE")"
  before_head="$(git -C "$ROOT" rev-parse HEAD)"

  if [[ "$status" != "open" ]]; then
    printf '\n最终状态已变为 %s，停止。\n' "$status"
    break
  fi
  if (( before >= limit )); then
    printf '\n本批已完成 %s/%s 轮，停止。\n' "$before" "$limit"
    break
  fi

  ordinal=$((before + 1))
  stamp="$(date +%Y%m%d_%H%M%S)"
  log="$run_dir/round_$(printf '%03d' "$ordinal")_${stamp}.log"
  final="$run_dir/round_$(printf '%03d' "$ordinal")_${stamp}_final.md"

  printf '\n===== 批次 %s：启动第 %s/%s 轮（全新 Codex）=====\n' "$batch_id" "$ordinal" "$limit"
  set +e
  codex exec \
    --approve-for-me \
    --skip-git-repo-check \
    -C "$ROOT" \
    --output-last-message "$final" \
    - < "$PROMPT" 2>&1 | tee "$log"
  codex_rc="${PIPESTATUS[0]}"
  set -e

  if (( codex_rc != 0 )); then
    printf '\nCodex 退出码为 %s；已停止，先检查：%s\n' "$codex_rc" "$log" >&2
    exit "$codex_rc"
  fi

  after="$(jq -r '.completed_iterations' "$STATE")"
  total_after="$(jq -r '.total_iterations' "$STATE")"
  after_head="$(git -C "$ROOT" rev-parse HEAD)"
  delta=$((after - before))
  total_delta=$((total_after - total_before))
  commit_delta="$(git -C "$ROOT" rev-list --count "$before_head..$after_head")"

  if (( commit_delta != 1 )); then
    printf '\nGit 协议违规：本次尝试产生了 %s 个 commit（应恰好为 1）。立即停止。\n' \
      "$commit_delta" >&2
    exit 4
  fi

  if (( delta == 0 && total_delta == 0 )); then
    printf '\n本轮未通过验证、失败记录已提交、计数未增加。脚本停止，供你检查或修改。\n'
    break
  fi
  if (( delta != 1 || total_delta != 1 )); then
    printf '\n协议违规：批次计数变化=%s，总计数变化=%s（都应为 1）。立即停止。\n' \
      "$delta" "$total_delta" >&2
    exit 3
  fi

  printf '\n第 %s 轮通过脚本计数检查。\n' "$ordinal"
  if (( after >= limit )); then
    printf '本批达到上限 %s/%s，停止。\n' "$after" "$limit"
    break
  fi

  if [[ "$auto_mode" == true ]]; then
    printf '自动模式：等待 2 秒后启动下一轮。按 Ctrl+C 可随时停止。\n'
    sleep 2
    continue
  fi

  printf '按 Enter 启动下一轮；输入 q 后回车可停止并修改文件：'
  read -r answer
  if [[ "$answer" == "q" || "$answer" == "Q" ]]; then
    printf '已在两轮之间安全停止。稍后使用 resume 继续。\n'
    break
  fi
done
