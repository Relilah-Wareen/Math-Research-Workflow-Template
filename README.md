# Math Research Workflow Template

这是不绑定任何数学命题的自动化研究工程。

完整中文说明见 `用户指南.md`。

使用顺序：

1. 填写 `notes/problem_statement.md` 的所有占位项；
2. 将其中 `setup_status: empty` 改为 `setup_status: locked`；
3. 在 `literature/user_references.md` 填写参考文献；
4. 运行 `./scripts/prepare_project.sh` 完成校验、状态初始化和本地提交；
5. 运行 `./scripts/run_research_supervisor_loop.sh start`。

停止、状态和恢复：

```bash
./scripts/stop_research_supervisor_loop.sh
./scripts/run_research_supervisor_loop.sh status
./scripts/run_research_supervisor_loop.sh resume
```

未锁定题目时，自动化必须停止，不能自行猜题。
