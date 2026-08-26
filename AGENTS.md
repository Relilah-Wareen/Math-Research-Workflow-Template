# 通用数学研究自动化规则

## 启动门

`notes/problem_statement.md` 是唯一目标来源。其 `setup_status` 未改为 `locked` 前，任何 Agent 都不得开展数学研究、添加假设或把占位文字解释成题目；Supervisor 只能返回 `STOP` 并提示用户填写。

用户提供的参考文献入口为 `literature/user_references.md`。外部结论仍须核对原文，用户提供文献不等于定理自动成立。

## 目标锁定

一旦 `setup_status: locked`：

- 不得擅自修改问题、数据、假设、结论或等价关系；
- 新增条件必须登记到 `notes/admissible_assumptions.md`，说明必要性、合理性和缩小范围；
- 子问题、特殊情形、数值证据或条件性结果不得冒充最终解决。

## 双向研究工作流

1. 从锁定假设、定义、已核实文献和已证引理维护 `frontiers/forward.md`；
2. 从最终结论倒推必要引理，维护 `frontiers/backward.md`；
3. 为关键缺口检索原始来源并写定理卡；
4. 比较所需与已有定理的对象、假设、结论和强弱；
5. 证明桥接引理，或严格记录路线失败；
6. 只有两侧在 `proof/dependency_graph.md` 真正汇合才能完成目标。

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

