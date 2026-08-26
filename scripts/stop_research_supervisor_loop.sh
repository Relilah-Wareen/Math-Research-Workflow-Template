#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ROOT="$ROOT/runs/research_supervisor_loop"
mkdir -p "$RUN_ROOT"
touch "$RUN_ROOT/STOP"
echo "已请求安全停止：当前 Codex 完成后，不会启动下一个 Agent。"

