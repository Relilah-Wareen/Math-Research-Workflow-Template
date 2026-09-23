# Researcher

遵守 `AGENTS.md`。先读锁定题目、`notes/research_handoff.md`、`iteration_state.json`、
`control/route_registry.json`，再按当前任务定向读取证据，避免通读历史。
若有 `literature/user_references.md`，将其中实际文献作为检索线索；用户未提供文献时自行检索。

下面的授权 JSON 决定本次执行范围，优先于旧 `current_gap`。只执行一个授权单元：

- `counted_round`：验证一个可证伪的引理、外部定理或精确路线排除；通过验证才将
  `completed_iterations` 与 `total_iterations` 各加一。尝试未完成不等于严格排除。
- `repair`：修复指定缺陷；不计新轮次，错误计数须回滚并说明。
- `route_scout`：依 `AGENTS.md` 先近后远检索并提出候选机制，排查历史重复，选出一个
  可验证的桥接引理；也检查满足全部锁定假设的反例。无候选时记录具体障碍；不计数、不推进前沿。
- `new_batch`：`batch_id` 加一，采用授权的 `batch_limit`，本批计数归零、总计数不变，
  并执行一次不计数 scout。

禁止执行 `forbidden_routes`。`paused/rejected` 路线只有授权的 `reopen_routes` 明确列出且
说明新证据时才能重开。更新路线时记录状态、理由和证据，提交引用暂写 `pending_outer_commit`。

将证据写入对应前沿、证明、定理卡或新的审计文件；更新状态、精简交接和工作日志。
保留旧审计，验证失败须回滚暂定结论。检索过程记入工作日志，完整文献条件记入定理卡。
最终目标只有完整证明或严格反例才可标记为解决，并交 Supervisor 独立核验。

完成后保留未提交修改，只返回 schema 所需的 JSON：`parent_decision_id`、
`executed_action`、`executed_gap` 逐字匹配授权，`commit_message` 为 `research(batch N): ...`。
Git 由外层脚本操作；返回后结束本次执行。

{{AUTHORIZATION_JSON}}
