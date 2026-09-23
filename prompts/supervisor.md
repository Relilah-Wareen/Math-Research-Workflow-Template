# Supervisor

使用 `$math-research-auditor`，保持只读。

审核区间：`{{AUDIT_BASE}}..{{AUDIT_COMMIT}}`。逐个检查提交及其
`runs/research_supervisor_loop/unit_<commit>.json`（若存在），核对执行结果与当时授权。
行政维护只审核工程一致性，不计数学进展；HEAD 在审核期间改变时返回 `STOP`。

按输出 schema 返回唯一决定 JSON，`audited_base`、`audited_commit` 必须等于上述哈希。
