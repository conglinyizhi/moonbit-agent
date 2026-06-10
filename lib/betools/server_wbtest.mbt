///|
fn unique_tmp_file(name : String) -> String {
  "/tmp/\{name}-\{@env.now()}.txt"
}

///|
test "tool_replace preview honors old_text without writing file" {
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
  let path = unique_tmp_file("betools-batch")
  @native.write_file(path, "a\nb\nc\nd\n")
  let spec = "[{\"file\":\"\{path}\",\"edits\":[{\"action\":\"insert-after\",\"start\":1,\"content\":\"x\"},{\"action\":\"replace-lines\",\"start\":3,\"end\":3,\"content\":\"C\"},{\"action\":\"delete-lines\",\"start\":4,\"end\":4}]}]"
  let result = tool_batch(Map([("spec", str(spec))]))
  @debug.assert_eq(@native.read_file(path), "a\nx\nb\nC\n")
  @debug.assert_eq(result.stringify().contains("\"edits\":3"), true)
}

///|
test "tool_batch preview does not write file" {
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
test "tool_trx_rollback reports native runtime downgrade" {
  let path = unique_tmp_file("betools-trx-rollback")
  @native.write_file(path, "a\nb\n")
  let _ = tool_insert(
    Map([("file", str(path)), ("after_line", num(1)), ("content", str("x"))]),
  )
  let status = tool_trx_status(Map::default())
  @debug.assert_eq(status.stringify().contains("\"used\":0"), true)
  let rollback = tool_trx_rollback(Map([("step", num(1))]))
  @debug.assert_eq(rollback.stringify().contains("\"rolled_back\":0"), true)
  @debug.assert_eq(rollback.stringify().contains("\"isError\":true"), true)
  @debug.assert_eq(@native.read_file(path), "a\nx\nb\n")
}

///|
test "tool_trx_commit reports zero committed snapshots" {
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
  @debug.assert_eq(committed.stringify().contains("\"committed\":0"), true)
  @debug.assert_eq(@native.read_file(path), "a\nB\n")
}
