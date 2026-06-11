# coding_agent_other

最简 MoonBit agent loop，包含：

- 通过远程 Chat Completions API 与模型交互
- 使用 `agent.toml` 保存模型、工具和 UI 配置
- 内置一个可原生编译的 `better-edit-tools` MCP server
- agent 启动时通过 MCP `tools/list` 动态发现工具 schema
- 工具调用会在 `agent.workdir` 指定的工作目录下执行
- `tools.better_edit_tools_cmd` 使用相对路径时，会相对于 agent 启动目录解析，而不是相对于 `agent.workdir`
- 提供最基础的 TUI/REPL 交互

## Build

```bash
moon build --target native
```

也可以直接使用：

```bash
make build
```

## Run Agent

先编辑 `agent.toml` 中的 API 配置，然后运行：

```bash
moon run cmd/agent --target native
```

或者：

```bash
make run
```

在 `2026-06-11` 这台机器上，`moon 0.1.20260610` 下连续多次执行 `moon run cmd/agent --target native` 和 `moon run cmd/better-edit-tools --target native` 都没有复现此前的 `tcc` 崩溃；但系统里仍保留 `2026-06-10` 的历史 core dump，因此如果你在其他机器或旧版本 toolchain 上仍遇到 native 运行崩溃，推荐的保守方式仍然是先 `moon build` 再直接执行生成的二进制。

本地命令：

- `/help`
- `/tools`
- `/toolhelp <tool>`
- `/toolschema <tool>`
- `/prompt`
- `/history`
- `/history full`
- `/savehistory [path]`
- `/savehistoryjson [path]`
- `/loadhistoryjson [path]`
- `/call <tool> <json>`
- `/saveconfig [path]`
- `/clear`
- `/exit`

如果本机 `moon run` 遇到 `tcc` 崩溃，可以先构建再直接运行可执行文件：

```bash
moon build cmd/agent --target native
./_build/native/debug/build/cmd/agent/agent.exe
```

`better-edit-tools` 同理：

```bash
moon build cmd/better-edit-tools --target native
./_build/native/debug/build/cmd/better-edit-tools/better-edit-tools.exe
```

## Run MCP Tool Server

```bash
./_build/native/debug/build/cmd/better-edit-tools/better-edit-tools.exe
```

该进程通过 stdio 提供 MCP `initialize`、`tools/list` 和 `tools/call`。

## Local E2E Tool Call Check

如果当前环境没有可用的外部模型 API，可以先运行仓库内的一键脚本验证 agent 的多轮 tool call 链路：

```bash
moon run scripts/run_mock_e2e.mbtx --target native .
```

或者：

```bash
make mock-e2e
```

这个脚本会：

- 构建 `cmd/agent` 和 `cmd/better-edit-tools` 的 native 可执行文件
- 启动本地 mock Chat Completions 服务
- 写入临时 `agent.toml`
- 驱动 agent 完成一轮 `be-read` 工具调用并检查最终续答

如果你想手工分步观察链路，也可以按下面的方式运行。

先准备样例文件并启动 mock 服务：

```bash
mkdir -p /tmp/moon-agent-e2e
printf 'alpha\nbeta\n' > /tmp/moon-agent-e2e/sample.txt
moon run scripts/mock_chat_completions.mbtx --target native
```

另开一个终端，写入一份临时配置：

```bash
cat > /tmp/moon-agent-e2e/agent.toml <<'EOF'
[model]
base_url = "http://127.0.0.1:18080"
model = "mock-model"
api_key = "test-key"
temperature = 0.2
max_tokens = 2048

[agent]
system_prompt = "You are a pragmatic coding agent. Use tools when needed and keep answers concise."
max_turns = 8
max_tool_calls_per_turn = 6
workdir = "/tmp/moon-agent-e2e"

[tools]
better_edit_tools_cmd = "/home/clyzhi/disk/ai_workspace/moonbit_space/coding_agent_other/_build/native/debug/build/cmd/better-edit-tools/better-edit-tools.exe"
better_edit_tools_args = []
startup_timeout_ms = 3000
call_timeout_ms = 20000

[ui]
show_timestamps = false
show_tool_calls = true
show_raw_tool_results = true
EOF
```

然后构建并运行 agent：

```bash
moon build cmd/agent --target native
moon build cmd/better-edit-tools --target native
printf 'read the file\n/exit\n' | ./_build/native/debug/build/cmd/agent/agent.exe --config /tmp/moon-agent-e2e/agent.toml
```

预期输出会先打印一条 `[tool] be-read ...`，再显示工具读取出的文件内容，最后输出带有 `FINAL:` 前缀的模型续答。这条用例验证了：

- agent 能读取 MCP `tools/list` 返回的真实 schema
- mock 模型能返回合法的 `tool_calls`
- agent 能完成“模型请求 -> 工具调用 -> 工具结果回填 -> 模型继续响应”的一整轮闭环

当前已知限制：

- 这条 e2e 用例验证的是本地 mock 服务，不是外部真实模型厂商 API
- 当前仓库默认从 `OPENAI_API_KEY` 读取密钥；如果没有可用密钥，agent 启动时会直接报缺少 API key
- 在 `2026-06-11` 当前环境里，直接探测 `https://api.openai.com/v1/models` 返回 `HTTP 403`，所以真实远端可用性仍取决于可访问区域、代理路径和可用账号配置
- `lib/agent/run.mbt` 现在已经把多轮 loop 拆成可注入的 driver seam，后续可以在不启动真实 HTTP/MCP 进程的前提下，直接用脚本化的模型回复和工具结果补充更细粒度的 wbtest
- `lib/agent/run_wbtest.mbt` 里已经提供 `run_scripted_turn` 这类测试 helper；后续新增 LLM 模拟测试时，优先复用这些 helper，而不是重复手写 reply/result 索引逻辑

## Current Native Notes

- `be-read`、`be-write`、`be-replace`、`be-insert`、`be-delete`、`be-batch` 已可直接通过 native MCP 路径使用。
- `chip_id` 和 `viewed_code_id` 已可用。
- `be-trx-commit`、`be-trx-rollback`、`be-trx-status` 现在会在当前工作目录持久化 `.moonagent-trx-*` 快照文件，并支持真实回滚。
