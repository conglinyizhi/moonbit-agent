///|
test "parse_tool_result includes metadata for model-visible content" {
  let raw = "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"1: hello\",\"_data\":{\"file\":\"/tmp/x.txt\",\"viewed_code_id\":\"abc123\"}}]}}\n"
  let result = parse_tool_result(raw)
  @debug.assert_eq(result.is_error, false)
  @debug.assert_eq(result.content_text.contains("1: hello"), true)
  @debug.assert_eq(result.content_text.contains("metadata:"), true)
  @debug.assert_eq(
    result.content_text.contains("\"viewed_code_id\":\"abc123\""),
    true,
  )
}

///|
test "parse_tool_definitions reads tools from mcp tools/list result" {
  let raw = "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"tools\":[{\"name\":\"be-read\",\"description\":\"Read file content with line numbers.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"file\":{\"type\":\"string\"},\"start\":{\"type\":\"integer\"}},\"required\":[\"file\",\"start\"]}},{\"name\":\"be-write\",\"description\":\"Write full file content.\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"file\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"}}}}]}}\n"
  let defs = parse_tool_definitions(raw)
  @debug.assert_eq(defs.length(), 2)
  @debug.assert_eq(defs[0].name, "be-read")
  @debug.assert_eq(defs[0].description, "Read file content with line numbers.")
  @debug.assert_eq(defs[0].input_schema.stringify().contains("\"start\""), true)
  @debug.assert_eq(defs[1].name, "be-write")
}

///|
test "command_string prefixes tool command with configured workdir" {
  let cfg = @config.default_config().tools
  let command = command_string(cfg, "/tmp/moon agent")
  @debug.assert_eq(command.has_prefix("cd '/tmp/moon agent' && "), true)
  @debug.assert_eq(
    command.contains(
      "_build/native/debug/build/cmd/better-edit-tools/better-edit-tools.exe",
    ),
    true,
  )
  @debug.assert_eq(
    command.contains(
      "'./_build/native/debug/build/cmd/better-edit-tools/better-edit-tools.exe'",
    ),
    false,
  )
}

///|
test "resolve_command_path expands relative executable path from agent cwd" {
  let cwd = @env.current_dir().unwrap_or(".")
  let resolved = resolve_command_path(
    "./_build/native/debug/build/cmd/better-edit-tools/better-edit-tools.exe",
  )
  @debug.assert_eq(resolved.has_prefix("\{cwd}/"), true)
}
