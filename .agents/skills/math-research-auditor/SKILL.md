---
name: math-research-auditor
description: Audit mathematical research units and issue the next structured decision in this repository’s Supervisor–Researcher loop. Use for research review, not ordinary repository maintenance.
---

# 数学研究审计

Supervisor 严格只读，遵守 `AGENTS.md`。题目未 `locked` 时返回 `STOP` 并提示填写。

## 读取与审核

先读唯一题目、精简交接、`iteration_state.json`、`control/route_registry.json` 和指定提交区间。
按 diff 与引用定向读取证明、审计和来源，不通读全部历史。逐个提交核对其执行 manifest 与
当时授权；授权优先于旧 `current_gap`，路线重开须有显式授权和新证据。

- 区分完整证明、已核实外部定理、严格路线排除、失败尝试和不计数审计；未完成证明不等于排除。
- 按 `AGENTS.md` 验证门重算关键推导，核对原文的版本、定理号、页码和完整条件。
  检查结论是否真的接入依赖图，不能把最终目标换名作为中间引理。
- 计数成功两项各加一；失败和 scout 不加。修复不得新增进展，可纠正旧错计数；
  新批只将本批计数归零。失败须回滚前沿和依赖边，保留旧审计。
- 每个研究单元应有外层脚本的一次提交，工作树干净，状态与交接一致。
  只有覆盖全部锁定假设和结论的证明或反例通过独立核验，才接受最终解决。

## 检查证明搜索是否推进

下一任务应先利用已证引理与双向前沿定位缺口，检查相似问题、邻近领域的原始方法。
若不能直接迁移，明确条件错配并选择可验证的桥接引理；已有明确障碍时才扩大到更远领域。
审核远领域类比能否还原为本问题的精确命题，避免只报方向或反复提出与最终目标同样困难的引理。
换线保留仍成立的引理与条件，不为新批次重置数学成果，也不为凑轮数制造名义进展。

## 决定

| decision | authorized_action | 适用条件 |
| --- | --- | --- |
| CONTINUE | counted_round | 当前路线有精确、单轮可证伪的下一缺口 |
| REPAIR | repair | 存在可修复的证明、标签、来源、计数或回滚缺陷 |
| SWITCH_ROUTE | route_scout | 路线停滞、循环或首门过宽；先做不计数探索 |
| NEW_BATCH | new_batch | 已达批次上限或路线族停滞；初始化并探索新批 |
| STOP | stop | 未锁题、目标解决、用户停止、缺少必要外部权限/数据，或无法自动安全修复的工程故障 |

目标仍开放且工程安全时，沿上述搜索推进，必要时检验满足全部假设的反例或不可能性机制。
候选失败、暂时无路线、问题困难均不构成 STOP 理由。新任务须明确输入、输出、成功/失败标准，
并排查历史重复；批次仅用于运行调度。

按 schema 填写唯一 `authorized_gap`、具体 `next_task`、被替代的 `superseded_gap`（无则空）、
`forbidden_routes` 和 `reopen_routes`（重开理由写入 `reason`）。
`batch_limit` 为 2–8；`audit_interval` 为 1–3，新路线、失败、修复或来源敏感时用 1，
仅近期计数单元连续通过且依赖清晰时用 2 或 3。决定 ID 由外层脚本生成。
