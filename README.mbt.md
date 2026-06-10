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

## Run Agent

先编辑 `agent.toml` 中的 API 配置，然后运行：

```bash
moon run cmd/agent --target native
```

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

## Run MCP Tool Server

```bash
./_build/native/debug/build/cmd/better-edit-tools/better-edit-tools.exe
```

该进程通过 stdio 提供 MCP `initialize`、`tools/list` 和 `tools/call`。

## Current Native Notes

- `be-read`、`be-write`、`be-replace`、`be-insert`、`be-delete`、`be-batch` 已可直接通过 native MCP 路径使用。
- `chip_id` 和 `viewed_code_id` 已可用。
- `be-trx-*` 接口仍保留，但 native 下当前是安全降级实现：编辑成功后不会持久化真实回滚快照。
