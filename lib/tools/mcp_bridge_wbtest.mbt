///|
test "resolve_command_path expands relative executable path from agent cwd" {
  let cwd = @env.current_dir().unwrap_or(".")
  let resolved = resolve_command_path(
    "./_build/native/debug/build/cmd/better-edit-tools/better-edit-tools.exe",
  )
  @debug.assert_eq(resolved.has_prefix("\{cwd}/"), true)
}

///|
test "resolve_workdir expands relative workdir from agent cwd" {
  let cwd = @env.current_dir().unwrap_or(".")
  let resolved = resolve_workdir("tmp/work")
  @debug.assert_eq(resolved, "\{cwd}/tmp/work")
}

///|
fn sample_tools_cfg() -> @config.ToolsConfig {
  @config.default_config().tools
}

///|
test "fetch_tool_definitions lists better-edit-tools schemas" {
  let result = fetch_tool_definitions(sample_tools_cfg(), ".")
  match result {
    Ok(defs) => {
      @debug.assert_eq(defs.length() > 0, true)
      @debug.assert_eq(defs.any(fn(def) { def.name == "be-read" }), true)
      @debug.assert_eq(defs.any(fn(def) { def.name == "be-trx-rollback" }), true)
    }
    Err(Failure(message~)) => {
      @debug.assert_eq(message, "__unexpected_error__")
    }
  }
}

///|
test "call_tool reads file through MCP bridge" {
  let path = "/tmp/mcp-bridge-call-tool.txt"
  @native.write_file(path, "alpha\nbeta\n") catch { _ => () }
  let result = call_tool(
    sample_tools_cfg(),
    ".",
    "be-read",
    "{\"file\":\"/tmp/mcp-bridge-call-tool.txt\",\"start\":1,\"end\":2}",
  )
  match result {
    Ok(tool_result) => {
      @debug.assert_eq(tool_result.is_error, false)
      @debug.assert_eq(tool_result.content_text.contains("1: alpha"), true)
    }
    Err(Failure(message~)) => {
      @debug.assert_eq(message, "__unexpected_error__")
    }
  }
}
