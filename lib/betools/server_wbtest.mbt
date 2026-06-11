///|
fn unique_tmp_file(name : String) -> String {
  "/tmp/\{name}-\{@env.now()}.txt"
}

///|
fn cleanup_trx_state() -> Unit {
  let _ = commit_snapshots()
}

///|
fn parse_mcp_call(raw : String) -> Json {
  let lines = raw
    .split("\n")
    .filter(line => line != "" && line.has_prefix("{"))
    .map(line => line.to_owned())
    .to_array()
  @json.parse(lines[lines.length() - 1]) catch {
    _ => json_text_result("failed to parse mcp output", true)
  }
}

///|
fn run_mcp_tool(name : String, arguments_json : String) -> Json {
  let request = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"wbtest\",\"version\":\"0.1.0\"}}}\n{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}\n{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"\{name}\",\"arguments\":\{arguments_json}}}\n"
  let output = @native.run_command(
    "./_build/native/debug/build/cmd/better-edit-tools/better-edit-tools.exe",
    stdin_data=request,
  ) catch {
    _ => return json_text_result("failed to run mcp tool", true)
  }
  parse_mcp_call(output)
}

///|
test "tool_replace preview honors old_text without writing file" {
  cleanup_trx_state()
  let path = unique_tmp_file("betools-preview")
  @native.write_file(path, "a\nb\nc\n")
  let result = tool_replace(
    Map([
      ("file", str(path)),
      ("start_line", num(2)),
      ("end_line", num(2)),
      ("old_text", str("b")),
      ("content", str("B")),
      ("preview", bool_json(true)),
    ]),
  )
  let after = @native.read_file(path)
  @debug.assert_eq(after, "a\nb\nc\n")
  @debug.assert_eq(result.stringify().contains("\"preview\":true"), true)
}

///|
test "tool_write supports files array with raw newline decoding" {
  cleanup_trx_state()
  let path_a = unique_tmp_file("betools-write-a")
  let path_b = unique_tmp_file("betools-write-b")
  let result = tool_write(
    Map([
      (
        "files",
        arr([
          obj([("file", str(path_a)), ("content", str("alpha\\nbeta"))]),
          obj([("file", str(path_b)), ("content", str("x\\ny"))]),
        ]),
      ),
      ("raw", bool_json(true)),
    ]),
  )
  @debug.assert_eq(@native.read_file(path_a), "alpha\nbeta")
  @debug.assert_eq(@native.read_file(path_b), "x\ny")
  @debug.assert_eq(result.stringify().contains("\"files\":2"), true)
}

///|
test "tool_batch applies descending edits in one file" {
  cleanup_trx_state()
  let path = unique_tmp_file("betools-batch")
  @native.write_file(path, "a\nb\nc\nd\n")
  let spec = "[{\"file\":\"\{path}\",\"edits\":[{\"action\":\"insert-after\",\"start\":1,\"content\":\"x\"},{\"action\":\"replace-lines\",\"start\":3,\"end\":3,\"content\":\"C\"},{\"action\":\"delete-lines\",\"start\":4,\"end\":4}]}]"
  let result = tool_batch(Map([("spec", str(spec))]))
  @debug.assert_eq(@native.read_file(path), "a\nx\nb\nC\n")
  @debug.assert_eq(result.stringify().contains("\"edits\":3"), true)
}

///|
test "tool_batch preview does not write file" {
  cleanup_trx_state()
  let path = unique_tmp_file("betools-batch-preview")
  @native.write_file(path, "a\nb\n")
  let spec = "[{\"file\":\"\{path}\",\"edits\":[{\"action\":\"replace-lines\",\"start\":2,\"end\":2,\"content\":\"B\"}]}]"
  let result = tool_batch(
    Map([("spec", str(spec)), ("preview", bool_json(true))]),
  )
  @debug.assert_eq(@native.read_file(path), "a\nb\n")
  @debug.assert_eq(result.stringify().contains("\"preview\":true"), true)
}

///|
test "tool_read rejects invalid start before touching file path" {
  let result = tool_read(
    Map([("file", str(".")), ("start", num(0))]),
  )
  @debug.assert_eq(result.stringify().contains("\"isError\":true"), true)
  @debug.assert_eq(result.stringify().contains("invalid line number"), true)
}

///|
test "tool_read reports directory path instead of crashing native reader" {
  let result = tool_read(
    Map([("file", str(".")), ("start", num(1))]),
  )
  @debug.assert_eq(result.stringify().contains("\"isError\":true"), true)
  @debug.assert_eq(result.stringify().contains("failed to read file"), true)
}

///|
test "tool_read through mcp bridge rejects invalid directory request without crashing" {
  let result = run_mcp_tool(
    "be-read",
    "{\"file\":\".\",\"start\":0}",
  )
  @debug.assert_eq(result.stringify().contains("\"isError\":true"), true)
  @debug.assert_eq(result.stringify().contains("invalid line number"), true)
}

///|
test "tool_trx_rollback restores prior file states" {
  cleanup_trx_state()
  let path = unique_tmp_file("betools-trx-rollback")
  @native.write_file(path, "a\nb\n")
  let _ = tool_insert(
    Map([("file", str(path)), ("after_line", num(1)), ("content", str("x"))]),
  )
  let _ = tool_replace(
    Map([
      ("file", str(path)),
      ("start", num(3)),
      ("end", num(3)),
      ("content", str("B")),
    ]),
  )
  let status = tool_trx_status(Map::default())
  @debug.assert_eq(status.stringify().contains("\"used\":2"), true)
  let rollback_one = tool_trx_rollback(Map([("step", num(1))]))
  @debug.assert_eq(rollback_one.stringify().contains("\"rolled_back\":1"), true)
  @debug.assert_eq(@native.read_file(path), "a\nx\nb\n")
  let rollback_two = tool_trx_rollback(Map([("step", num(1))]))
  @debug.assert_eq(rollback_two.stringify().contains("\"rolled_back\":1"), true)
  let status_after = tool_trx_status(Map::default())
  @debug.assert_eq(status_after.stringify().contains("\"used\":0"), true)
  @debug.assert_eq(@native.read_file(path), "a\nb\n")
}

///|
test "tool_trx_rollback through mcp bridge returns real snapshot result" {
  cleanup_trx_state()
  let path = unique_tmp_file("betools-trx-mcp")
  @native.write_file(path, "a\nb\n")
  let direct = run_mcp_tool(
    "be-insert",
    "{\"file\":\"\{path}\",\"after_line\":1,\"content\":\"x\"}",
  )
  @debug.assert_eq(direct.stringify().contains("\"isError\":true"), false)
  let rollback = run_mcp_tool("be-trx-rollback", "{\"step\":1}")
  @debug.assert_eq(rollback.stringify().contains("\"isError\":true"), false)
  @debug.assert_eq(rollback.stringify().contains("\"rolled_back\":1"), true)
  @debug.assert_eq(@native.read_file(path), "a\nb\n")
}

///|
test "tool_trx_commit clears persisted queue" {
  cleanup_trx_state()
  let path = unique_tmp_file("betools-trx-commit")
  @native.write_file(path, "a\nb\n")
  let _ = tool_replace(
    Map([
      ("file", str(path)),
      ("start", num(2)),
      ("end", num(2)),
      ("content", str("B")),
    ]),
  )
  let committed = tool_trx_commit(Map::default())
  @debug.assert_eq(committed.stringify().contains("\"committed\":1"), true)
  let status = tool_trx_status(Map::default())
  @debug.assert_eq(status.stringify().contains("\"used\":0"), true)
  @debug.assert_eq(@native.read_file(path), "a\nB\n")
}
