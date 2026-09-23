# Math Research Workflow Template

一个独立、通用的数学研究工作流模板，用于文献检索、双向证明搜索、逐步验证与自动审计。

**也可以直接向 Codex 提问，让它查看仓库并指导使用。** 例如：“请阅读这个仓库的 README，
指导我填写研究命题、选择模型并启动工作流。”

唯一执行流程：**Supervisor 只读审核 → Researcher 完成一个授权单元 → 外层脚本校验并提交 → 再审核**。
每次调用使用新进程，通过文件交接；Researcher 不操作 Git，脚本只做本地提交。

研究以文献引导证明搜索：先找相似问题和邻近领域的方法，核对条件并提炼桥接引理；
遇到明确障碍后向更远领域扩展。正向保留已验证引理，反向拆解最终目标，每次验证一个缺口，
直到两侧依赖真正接通。分批仅控制运行，不预设研究路线或要求凑轮数。

## 配置题目

需要本机已配置可用的 `codex`，以及 `jq`、`git`。同一项目只运行一个编排进程。

1. 填写 `notes/problem_statement.md`，把 `setup_status: empty` 改为 `setup_status: locked`。
2. 可选：在 `literature/user_references.md` 提供文献线索。不提供也可启动，Researcher 自行检索。
3. 运行初始化命令，检查占位符并创建本地锁题提交：

```bash
./scripts/prepare_project.sh
```

未锁题时禁止研究。启动和恢复要求工作树干净，先用 `git status --short` 检查。

## 运行

终端一：

```bash
./scripts/run_research_supervisor_loop.sh start --model gpt-6-astra --max-tokens 200000
```

终端二查看状态或请求安全停止：

```bash
./scripts/run_research_supervisor_loop.sh status
./scripts/stop_research_supervisor_loop.sh
```

停止请求在当前 Agent 完成后生效。等待编排退出，再恢复：

```bash
./scripts/run_research_supervisor_loop.sh resume --model gpt-6-astra --max-tokens 400000
```

`--max-tokens` 为累计输入与输出 token 的停止阈值，省略或设为 `0` 表示不限。
它在 Agent 调用之间检查，单次调用可能越过阈值；恢复时传入新的累计上限。
Supervisor 返回 `STOP` 后不能 `resume`，处理原因后用 `start` 重新审核。

`--model MODEL_ID`（或 `-m MODEL_ID`）为两种角色选择模型，优先于 `CODEX_MODEL` 环境变量；
两者都未指定时默认使用 `gpt-6-astra`。使用 5.6、6 或以后的模型时，传入当前 Codex 环境中
可用的完整模型标识即可；脚本不限定模型列表，也不将简称自动映射为某个模型。
每次 `start` / `resume` 都按本次参数与环境选模型；恢复时也可以更换模型。
参数帮助：`./scripts/run_research_supervisor_loop.sh --help`。

瞬时网络/容量错误默认最多重试 5 次，可用 `RESEARCH_LOOP_MAX_RETRIES` 调整，设为 `0` 关闭；
若失败调用已修改工作树或 HEAD，则停止供检查，避免重复执行同一研究单元。
状态、token 统计、授权和原始日志位于 `runs/research_supervisor_loop/`，不进入 Git。

## 文件职责

| 文件 | 用途 |
| --- | --- |
| `AGENTS.md` | 目标锁定、双向研究与验证规则 |
| `prompts/researcher.md` | 完整单轮闭环、文献核验、路线探索、修复、分批与交接 |
| `prompts/supervisor.md` | 只读审核入口、授权协议与结构化决定 |
| `.agents/skills/math-research-auditor/SKILL.md` | 逐项数学审计、计数回滚、路线质量与决定标准 |
| `scripts/` | 初始化、编排、停止、JSON 协议与回归测试 |
| `notes/` | 唯一题目、附加假设、精简交接 |
| `frontiers/`、`proof/`、`audit/` | 正反向前沿、证明依赖和逐次审计（按需创建） |
| `literature/` | 用户文献与核实后的定理卡 |
| `control/route_registry.json` | 路线状态与重开证据 |
| `iteration_state.json`、`work_log.md` | 数学状态、计数与工作记录 |

研究步骤由角色提示词和审计 Skill 定义，脚本负责初始化、编排与停止，检索记录写入工作日志。

测试使用临时仓库和模拟 Agent，不调用模型：

```bash
bash scripts/tests/test_workflow.sh
```
