# 通用数学研究自动化规则

## 启动门

`notes/problem_statement.md` 是唯一目标来源。其 `setup_status` 未改为 `locked` 前，任何 Agent 都不得开展数学研究、添加假设或把占位文字解释成题目；Supervisor 只能返回 `STOP` 并提示用户填写。

用户可只提供命题；`literature/user_references.md` 是可选的参考文献入口，不是启动条件。
Researcher 可自行检索文献，有用户文献时将其作为线索。两类来源均须核对原文，不能直接视为已成立定理。

## 目标锁定

一旦 `setup_status: locked`：

- 不得擅自修改问题、数据、假设、结论或等价关系；
- 新增条件必须登记到 `notes/admissible_assumptions.md`，说明必要性、合理性和缩小范围；
- 子问题、特殊情形、数值证据或条件性结果不得冒充最终解决。

## 双向研究工作流

1. 从锁定假设、定义、已核实文献和已证引理维护 `frontiers/forward.md`，从最终结论倒推必要引理维护 `frontiers/backward.md`，选定当前缺口；
2. 先检索相似问题与邻近领域的原始文献，比较已有方法与当前缺口的对象、假设、结论和强弱，将可用定理写入定理卡；
3. 可迁移的方法先尝试直接应用或提出桥接引理。若邻近方法不适用或停滞，记录具体错配，再逐步扩展到更远领域，提取能回到本问题的机制；无需穷尽近邻文献才可扩展；
4. 把候选机制写成有明确输入、输出、成功和失败标准的单个引理，验证后步进；类比或检索命中本身不算证明；
5. 保留已验证引理及其条件和依赖，后续轮次据此推进；失败时只撤回未成立的结论及受影响依赖，并记录障碍；
6. 只有两侧在 `proof/dependency_graph.md` 真正汇合才能完成目标。批次是运行控制，不规定证明路径或要求凑足轮数。

## 状态标签与验证门

数学陈述必须标记为 `[外部定理已核实]`、`[完全证明]`、`[条件性引理]`、`[候选猜想]`、`[已严格排除]` 或 `[开放缺口]`。

计数前必须复述完整假设与结论，核对来源正文，检查反例、边界情形、函数空间、正则性、对象兼容性、依赖循环和与主目标的真实连接。失败须回滚暂定前沿和依赖边，且不得增加计数。

## 文件职责

- `notes/problem_statement.md`：用户填写并锁定的唯一题目；
- `literature/user_references.md`：用户提供的参考文献；
- `notes/admissible_assumptions.md`：新增假设登记；
- `notes/research_handoff.md`：精简交接；
- `frontiers/`、`proof/`、`audit/`、`literature/theorem_cards.md`：研究证据；
- `control/route_registry.json`：路线状态；
- `iteration_state.json`、`work_log.md`：自动化状态。

自动编排中 Researcher 不操作 Git；外层脚本核对授权并提交。Supervisor 严格只读。
