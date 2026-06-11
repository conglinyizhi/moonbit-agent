///|
const VERSION = "0.1.0"

///|
const MAX_SNAPSHOTS = 30

///|
priv struct SnapshotPushResult {
  id : String
  warning : String
}

priv struct SnapshotRecord {
  id : String
  tool : String
  file : String
  before_content : String
  after_content : String
  summary : String
  created_at : String
}

///|
fn obj(entries : Array[(String, Json)]) -> Json {
  Json::object(Map(entries))
}

///|
fn arr(items : Array[Json]) -> Json {
  Json::array(items)
}

///|
fn str(value : String) -> Json {
  Json::string(value)
}

///|
fn num(value : Int) -> Json {
  Json::number(Double::from_int(value))
}

///|
fn bool_json(value : Bool) -> Json {
  Json::boolean(value)
}

///|
fn shell_quote(input : String) -> String {
  "'\{input.replace(old="'", new="'\"'\"'")}'"
}

///|
fn print_help() -> Unit {
  println("better-edit-tools " + VERSION)
  println("")
  println("Usage:")
  println("  better-edit-tools [--lang <zh|en>] [--version] [--help]")
  println("")
  println("Runs the MCP server over stdio by default.")
}

///|
fn handle_cli() -> Bool {
  let args = @env.args()
  let mut i = 1
  while i < args.length() {
    match args[i] {
      "--help" | "-h" => {
        print_help()
        return false
      }
      "--version" | "-V" => {
        println(VERSION)
        return false
      }
      "--lang" => i += 1
      _ => ()
    }
    i += 1
  }
  true
}

///|
fn json_error(code : Int, message : String, id? : Json = Json::null()) -> Json {
  obj([
    ("jsonrpc", str("2.0")),
    ("id", id),
    ("error", obj([("code", num(code)), ("message", str(message))])),
  ])
}

///|
fn json_ok(id : Json, result : Json) -> Json {
  obj([("jsonrpc", str("2.0")), ("id", id), ("result", result)])
}

///|
fn json_text_result(text : String, is_error : Bool) -> Json {
  let content = arr([obj([("type", str("text")), ("text", str(text))])])
  let items : Array[(String, Json)] = [("content", content)]
  if is_error {
    items.push(("isError", bool_json(true)))
  }
  obj(items)
}

///|
fn json_text_result_data(text : String, is_error : Bool, data : Json) -> Json {
  let content = arr([
    obj([("type", str("text")), ("text", str(text)), ("_data", data)]),
  ])
  let items : Array[(String, Json)] = [("content", content)]
  if is_error {
    items.push(("isError", bool_json(true)))
  }
  obj(items)
}

///|
fn schema_read() -> Json {
  obj([
    ("name", str("be-read")),
    ("description", str("Read file content with line numbers.")),
    (
      "inputSchema",
      obj([
        ("type", str("object")),
        (
          "properties",
          obj([
            ("file", obj([("type", str("string"))])),
            ("start", obj([("type", str("integer"))])),
            ("end", obj([("type", str("integer"))])),
            ("brief", obj([("type", str("boolean"))])),
          ]),
        ),
        ("required", arr([str("file"), str("start")])),
      ]),
    ),
  ])
}

///|
fn schema_write() -> Json {
  obj([
    ("name", str("be-write")),
    ("description", str("Write full file content.")),
    (
      "inputSchema",
      obj([
        ("type", str("object")),
        (
          "properties",
          obj([
            ("file", obj([("type", str("string"))])),
            ("content", obj([("type", str("string"))])),
            (
              "files",
              obj([
                ("type", str("array")),
                (
                  "items",
                  obj([
                    ("type", str("object")),
                    (
                      "properties",
                      obj([
                        ("file", obj([("type", str("string"))])),
                        ("content", obj([("type", str("string"))])),
                      ]),
                    ),
                  ]),
                ),
              ]),
            ),
            ("preview", obj([("type", str("boolean"))])),
            ("brief", obj([("type", str("boolean"))])),
            ("raw", obj([("type", str("boolean"))])),
          ]),
        ),
      ]),
    ),
  ])
}

///|
fn schema_replace() -> Json {
  obj([
    ("name", str("be-replace")),
    ("description", str("Replace a line range.")),
    (
      "inputSchema",
      obj([
        ("type", str("object")),
        (
          "properties",
          obj([
            ("file", obj([("type", str("string"))])),
            ("start", obj([("type", str("integer"))])),
            ("end", obj([("type", str("integer"))])),
            ("start_line", obj([("type", str("integer"))])),
            ("end_line", obj([("type", str("integer"))])),
            ("old", obj([("type", str("string"))])),
            ("old_text", obj([("type", str("string"))])),
            ("content", obj([("type", str("string"))])),
            ("viewed_code_id", obj([("type", str("string"))])),
            ("preview", obj([("type", str("boolean"))])),
            ("brief", obj([("type", str("boolean"))])),
            ("raw", obj([("type", str("boolean"))])),
          ]),
        ),
        (
          "required",
          arr([str("file"), str("start"), str("end"), str("content")]),
        ),
      ]),
    ),
  ])
}

///|
fn schema_insert() -> Json {
  obj([
    ("name", str("be-insert")),
    ("description", str("Insert content after a line.")),
    (
      "inputSchema",
      obj([
        ("type", str("object")),
        (
          "properties",
          obj([
            ("file", obj([("type", str("string"))])),
            ("after_line", obj([("type", str("integer"))])),
            ("line", obj([("type", str("integer"))])),
            ("content", obj([("type", str("string"))])),
            ("preview", obj([("type", str("boolean"))])),
            ("brief", obj([("type", str("boolean"))])),
            ("raw", obj([("type", str("boolean"))])),
          ]),
        ),
        ("required", arr([str("file"), str("content")])),
      ]),
    ),
  ])
}

///|
fn schema_delete() -> Json {
  obj([
    ("name", str("be-delete")),
    ("description", str("Delete a line range.")),
    (
      "inputSchema",
      obj([
        ("type", str("object")),
        (
          "properties",
          obj([
            ("file", obj([("type", str("string"))])),
            ("start", obj([("type", str("integer"))])),
            ("end", obj([("type", str("integer"))])),
            ("start_line", obj([("type", str("integer"))])),
            ("end_line", obj([("type", str("integer"))])),
            ("preview", obj([("type", str("boolean"))])),
            ("brief", obj([("type", str("boolean"))])),
          ]),
        ),
      ]),
    ),
  ])
}

///|
fn schema_func_range() -> Json {
  obj([
    ("name", str("be-func-range")),
    (
      "description",
      str("Approximate enclosing brace/function range for a line."),
    ),
    (
      "inputSchema",
      obj([
        ("type", str("object")),
        (
          "properties",
          obj([
            ("file", obj([("type", str("string"))])),
            ("line", obj([("type", str("integer"))])),
          ]),
        ),
        ("required", arr([str("file"), str("line")])),
      ]),
    ),
  ])
}

///|
fn schema_balance() -> Json {
  obj([
    ("name", str("be-balance")),
    ("description", str("Check simple bracket and quote balance for a file.")),
    (
      "inputSchema",
      obj([
        ("type", str("object")),
        (
          "properties",
          obj([
            ("file", obj([("type", str("string"))])),
            ("verbose", obj([("type", str("boolean"))])),
          ]),
        ),
        ("required", arr([str("file")])),
      ]),
    ),
  ])
}

///|
fn schema_tag_range() -> Json {
  obj([
    ("name", str("be-tag-range")),
    ("description", str("Approximate enclosing HTML/XML tag range for a line.")),
    (
      "inputSchema",
      obj([
        ("type", str("object")),
        (
          "properties",
          obj([
            ("file", obj([("type", str("string"))])),
            ("line", obj([("type", str("integer"))])),
          ]),
        ),
        ("required", arr([str("file"), str("line")])),
      ]),
    ),
  ])
}

///|
fn schema_insert_chip() -> Json {
  obj([
    ("name", str("be-insert-chip")),
    ("description", str("Insert content from a file URI or chip cache.")),
    (
      "inputSchema",
      obj([
        ("type", str("object")),
        (
          "properties",
          obj([
            ("from", obj([("type", str("string"))])),
            ("to", obj([("type", str("string"))])),
          ]),
        ),
      ]),
    ),
  ])
}

///|
fn schema_batch() -> Json {
  obj([
    ("name", str("be-batch")),
    (
      "description",
      str("Apply multiple line-based edits across one or more files."),
    ),
    (
      "inputSchema",
      obj([
        ("type", str("object")),
        (
          "properties",
          obj([
            ("spec", obj([("type", str("string"))])),
            ("preview", obj([("type", str("boolean"))])),
            ("brief", obj([("type", str("boolean"))])),
          ]),
        ),
        ("required", arr([str("spec")])),
      ]),
    ),
  ])
}

///|
fn schema_trx_commit() -> Json {
  obj([
    ("name", str("be-trx-commit")),
    ("description", str("Commit all pending edit snapshots (clear the queue).")),
    ("inputSchema", obj([("type", str("object")), ("properties", obj([]))])),
  ])
}

///|
fn schema_trx_rollback() -> Json {
  obj([
    ("name", str("be-trx-rollback")),
    ("description", str("Roll back the last N edit snapshots from the queue.")),
    (
      "inputSchema",
      obj([
        ("type", str("object")),
        ("properties", obj([("step", obj([("type", str("integer"))]))])),
        ("required", arr([str("step")])),
      ]),
    ),
  ])
}

///|
fn schema_trx_status() -> Json {
  obj([
    ("name", str("be-trx-status")),
    ("description", str("Show pending edit snapshots and queue usage.")),
    ("inputSchema", obj([("type", str("object")), ("properties", obj([]))])),
  ])
}

///|
fn list_tools_result() -> Json {
  obj([
    (
      "tools",
      arr([
        schema_read(),
        schema_write(),
        schema_replace(),
        schema_insert(),
        schema_delete(),
        schema_batch(),
        schema_func_range(),
        schema_balance(),
        schema_tag_range(),
        schema_insert_chip(),
        schema_trx_commit(),
        schema_trx_rollback(),
        schema_trx_status(),
      ]),
    ),
  ])
}

///|
fn get_string(map : Map[String, Json], key : String) -> String? {
  match map.get(key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn get_int(map : Map[String, Json], key : String) -> Int? {
  match map.get(key) {
    Some(Number(value, ..)) => Some(value.to_int())
    _ => None
  }
}

///|
fn get_bool(map : Map[String, Json], key : String) -> Bool {
  match map.get(key) {
    Some(True) => true
    _ => false
  }
}

///|
fn decode_raw_content(content : String, raw : Bool) -> String {
  if raw {
    content
    .replace(old="\\r\\n", new="\n")
    .replace(old="\\n", new="\n")
    .replace(old="\\t", new="\t")
  } else {
    content
  }
}

///|
fn normalized_line_block(content : String) -> String {
  let normalized = content.replace(old="\r\n", new="\n")
  let mut end = normalized.length()
  while end > 0 && normalized[end - 1] == '\n' {
    end -= 1
  }
  normalized[:end].to_owned()
}

///|
fn file_total_lines(lines : Array[String]) -> Int {
  if lines.length() > 0 && lines[lines.length() - 1] == "" {
    lines.length() - 1
  } else {
    lines.length()
  }
}

///|
fn line_block(lines : Array[String], start : Int, end : Int) -> String {
  let out : Array[String] = []
  for i in start..<(end + 1) {
    if i >= 1 && i <= file_total_lines(lines) {
      out.push(lines[i - 1])
    }
  }
  out.join("\n")
}

///|
fn sort_batch_edits_desc(
  edits : Array[(String, Int, Int, String)],
) -> Array[(String, Int, Int, String)] {
  let out = edits.copy()
  let n = out.length()
  for i in 0..<n {
    for j in (i + 1)..<n {
      let (_, si, _, _) = out[i]
      let (_, sj, _, _) = out[j]
      if sj > si {
        let tmp = out[i]
        out[i] = out[j]
        out[j] = tmp
      }
    }
  }
  out
}

///|
fn parse_batch_spec(
  spec : String,
) -> Array[(String, Array[(String, Int, Int, String)])]? {
  let parsed = @json.parse(spec) catch { _ => return None }
  match parsed {
    Array(files) => {
      let grouped : Array[(String, Array[(String, Int, Int, String)])] = []
      for file_item in files {
        let file_obj = match file_item {
          Object(obj) => obj
          _ => return None
        }
        let file = match get_string(file_obj, "file") {
          Some(value) => value
          None => return None
        }
        let edits_json = match file_obj.get("edits") {
          Some(Array(items)) => items
          _ => return None
        }
        let edits : Array[(String, Int, Int, String)] = []
        for edit_item in edits_json {
          let edit_obj = match edit_item {
            Object(obj) => obj
            _ => return None
          }
          let action = match get_string(edit_obj, "action") {
            Some(value) => value
            None => return None
          }
          match action {
            "replace-lines" => {
              let start = match get_int(edit_obj, "start") {
                Some(value) => value
                None => return None
              }
              let end = match get_int(edit_obj, "end") {
                Some(value) => value
                None => return None
              }
              let content = match get_string(edit_obj, "content") {
                Some(value) => value
                None => return None
              }
              edits.push((action, start, end, content))
            }
            "insert-after" => {
              let line = match get_int(edit_obj, "start") {
                Some(value) => value
                None =>
                  match get_int(edit_obj, "line") {
                    Some(value) => value
                    None => return None
                  }
              }
              let content = match get_string(edit_obj, "content") {
                Some(value) => value
                None => return None
              }
              edits.push((action, line, line, content))
            }
            "delete-lines" => {
              let start = match get_int(edit_obj, "start") {
                Some(value) => value
                None => return None
              }
              let end = get_int(edit_obj, "end").unwrap_or(start)
              edits.push((action, start, end, ""))
            }
            _ => return None
          }
        }
        grouped.push((file, edits))
      }
      Some(grouped)
    }
    _ => None
  }
}

///|
fn split_lines_keep_empty(content : String) -> Array[String] {
  let lines : Array[String] = []
  for line in content.split("\n") {
    lines.push(line.to_owned())
  }
  lines
}

///|
fn ensure_chip_dir() -> Bool {
  true
}

///|
fn ensure_view_dir() -> Bool {
  true
}

///|
fn chip_index_path() -> String {
  ".moonagent-chip-index.txt"
}

///|
fn chip_path(chip_id : String) -> String {
  ".moonagent-chip-\{chip_id}.txt"
}

///|
fn view_path(view_id : String) -> String {
  ".moonagent-view-\{view_id}.json"
}

///|
fn trx_index_path() -> String {
  ".moonagent-trx-index.json"
}

///|
fn trx_snapshot_path(id : String) -> String {
  ".moonagent-trx-\{id}.json"
}

///|
fn stable_id(seed : String) -> String {
  let mut checksum = 17
  for ch in seed {
    checksum = checksum * 31 + ch.to_int()
  }
  "\{@env.now()}-\{checksum.abs()}-\{seed.length()}"
}

///|
fn delete_path(path : String) -> Unit {
  let cwd = @env.current_dir().unwrap_or(".")
  let command = "cd \{shell_quote(cwd)} && rm -f \{shell_quote(path)}"
  ignore(@native.run_command(command) catch { _ => "" })
}

///|
fn snapshot_to_json(snapshot : SnapshotRecord) -> Json {
  obj([
    ("id", str(snapshot.id)),
    ("tool", str(snapshot.tool)),
    ("file", str(snapshot.file)),
    ("before_content", str(snapshot.before_content)),
    ("after_content", str(snapshot.after_content)),
    ("summary", str(snapshot.summary)),
    ("created_at", str(snapshot.created_at)),
  ])
}

///|
fn parse_snapshot_json(value : Json) -> SnapshotRecord? {
  match value {
    Object(root) => {
      let id_opt = get_string(root, "id")
      let tool_opt = get_string(root, "tool")
      let file_opt = get_string(root, "file")
      let before_opt = get_string(root, "before_content")
      let after_opt = get_string(root, "after_content")
      let summary_opt = get_string(root, "summary")
      let created_at_opt = get_string(root, "created_at")
      if id_opt is None ||
        tool_opt is None ||
        file_opt is None ||
        before_opt is None ||
        after_opt is None ||
        summary_opt is None ||
        created_at_opt is None {
        None
      } else {
        Some({
          id: id_opt.unwrap(),
          tool: tool_opt.unwrap(),
          file: file_opt.unwrap(),
          before_content: before_opt.unwrap(),
          after_content: after_opt.unwrap(),
          summary: summary_opt.unwrap(),
          created_at: created_at_opt.unwrap(),
        })
      }
    }
    _ => None
  }
}

///|
fn load_snapshot_ids() -> Array[String] {
  let raw = @native.read_file(trx_index_path()) catch { _ => return [] }
  let parsed = @json.parse(raw) catch { _ => return [] }
  match parsed {
    Array(items) => {
      let ids : Array[String] = []
      for item in items {
        match item {
          String(id) => ids.push(id)
          _ => ()
        }
      }
      ids
    }
    _ => []
  }
}

///|
fn save_snapshot_ids(ids : Array[String]) -> Unit {
  let rendered = arr(ids.map(id => str(id))).stringify()
  @native.write_file(trx_index_path(), rendered) catch { _ => () }
}

///|
fn load_snapshot(id : String) -> SnapshotRecord? {
  let raw = @native.read_file(trx_snapshot_path(id)) catch { _ => return None }
  let parsed = @json.parse(raw) catch { _ => return None }
  parse_snapshot_json(parsed)
}

///|
fn save_snapshot(snapshot : SnapshotRecord) -> Bool {
  @native.write_file(
    trx_snapshot_path(snapshot.id),
    snapshot_to_json(snapshot).stringify(),
  ) catch {
    _ => return false
  }
  true
}

///|
fn delete_snapshot(id : String) -> Unit {
  delete_path(trx_snapshot_path(id))
}

///|
fn collect_snapshots() -> Array[SnapshotRecord] {
  let snapshots : Array[SnapshotRecord] = []
  for id in load_snapshot_ids() {
    match load_snapshot(id) {
      Some(snapshot) => snapshots.push(snapshot)
      None => ()
    }
  }
  snapshots
}

///|
fn push_snapshot(
  tool : String,
  file : String,
  before_content : String,
  after_content : String,
  summary : String,
) -> SnapshotPushResult {
  let id = stable_id(
    "\{tool}|\{file}|\{summary}|\{before_content.length()}|\{after_content.length()}",
  )
  let snapshot : SnapshotRecord = {
    id: id,
    tool: tool,
    file: file,
    before_content: before_content,
    after_content: after_content,
    summary: summary,
    created_at: "\{@env.now()}",
  }
  if !save_snapshot(snapshot) {
    return { id: id, warning: "failed to persist snapshot" }
  }
  let ids = load_snapshot_ids()
  ids.push(id)
  let mut warning = ""
  while ids.length() > MAX_SNAPSHOTS {
    let dropped = ids.remove(0)
    delete_snapshot(dropped)
    warning = "snapshot queue full; evicted oldest snapshot"
  }
  save_snapshot_ids(ids)
  { id: id, warning: warning }
}

///|
fn commit_snapshots() -> Int {
  let ids = load_snapshot_ids()
  for id in ids {
    delete_snapshot(id)
  }
  delete_path(trx_index_path())
  ids.length()
}

///|
fn rollback_snapshots(step : Int) -> (Int, Array[String]) {
  if step <= 0 {
    return (0, ["step must be positive"])
  }
  let ids = load_snapshot_ids()
  if ids.is_empty() {
    return (0, [])
  }
  let requested = if step > ids.length() { ids.length() } else { step }
  let errors : Array[String] = []
  let kept : Array[String] = []
  for i in 0..<(ids.length() - requested) {
    kept.push(ids[i])
  }
  let mut rolled_back = 0
  let mut idx = ids.length()
  while idx > ids.length() - requested {
    idx -= 1
    let id = ids[idx]
    match load_snapshot(id) {
      Some(snapshot) => {
        @native.write_file(snapshot.file, snapshot.before_content) catch {
          _ => {
            errors.push("failed to restore \{snapshot.file}")
            kept.push(id)
            continue
          }
        }
        rolled_back += 1
        delete_snapshot(id)
      }
      None => errors.push("missing snapshot \{id}")
    }
  }
  save_snapshot_ids(kept)
  if kept.is_empty() {
    delete_path(trx_index_path())
  }
  (rolled_back, errors)
}

///|
fn save_chip(content : String) -> String? {
  if !ensure_chip_dir() {
    return None
  }
  let id = stable_id(content)
  @native.write_file(chip_path(id), content) catch {
    _ => return None
  }
  let existing_index = @native.read_file(chip_index_path()) catch { _ => "" }
  let next_index = if existing_index == "" {
    id
  } else {
    let builder = StringBuilder::StringBuilder()
    builder.write_string(existing_index)
    builder.write_string("\n")
    builder.write_string(id)
    builder.to_string()
  }
  @native.write_file(chip_index_path(), next_index) catch {
    _ => ()
  }
  Some(id)
}

///|
fn save_view(
  file : String,
  start : Int,
  end : Int,
  content : String,
) -> String? {
  if !ensure_view_dir() {
    return None
  }
  let view_id = stable_id("\{file}|\{start}|\{end}|\{content}")
  let payload = obj([
    ("file", str(file)),
    ("start", num(start)),
    ("end", num(end)),
    ("content", str(content)),
  ]).stringify()
  @native.write_file(view_path(view_id), payload) catch {
    _ => return None
  }
  Some(view_id)
}

///|
fn read_chip(chip_id : String) -> String? {
  Some(@native.read_file(chip_path(chip_id))) catch {
    _ => None
  }
}

///|
fn read_view(view_id : String) -> (String, Int, Int, String)? {
  let raw = @native.read_file(view_path(view_id)) catch { _ => return None }
  let parsed = @json.parse(raw) catch { _ => return None }
  match parsed {
    Object(root) => {
      let file_opt = get_string(root, "file")
      let start_opt = get_int(root, "start")
      let end_opt = get_int(root, "end")
      let content_opt = get_string(root, "content")
      if file_opt is None ||
        start_opt is None ||
        end_opt is None ||
        content_opt is None {
        None
      } else {
        Some(
          (
            file_opt.unwrap(),
            start_opt.unwrap(),
            end_opt.unwrap(),
            content_opt.unwrap(),
          ),
        )
      }
    }
    _ => None
  }
}

///|
fn list_chip_ids() -> Array[String] {
  if !ensure_chip_dir() {
    return []
  }
  let output = @native.read_file(chip_index_path()) catch { _ => return [] }
  let ids : Array[String] = []
  for line in output.split("\n") {
    let id = line.trim().to_owned()
    if id != "" {
      ids.push(id)
    }
  }
  ids
}

///|
fn join_lines(lines : Array[String]) -> String {
  lines.join("\n")
}

///|
fn render_line_range(lines : Array[String], start : Int, end : Int) -> String {
  let out : Array[String] = []
  for i in start..<(end + 1) {
    if i >= 1 && i <= lines.length() {
      out.push("\{i}: \{lines[i - 1]}")
    }
  }
  out.join("\n")
}

///|
fn tool_read(arguments : Map[String, Json]) -> Json {
  let file_opt = get_string(arguments, "file")
  if file_opt is None {
    return json_text_result("missing string field `file`", true)
  }
  let start_opt = get_int(arguments, "start")
  if start_opt is None {
    return json_text_result("missing integer field `start`", true)
  }
  let file = file_opt.unwrap()
  let start = start_opt.unwrap()
  if start < 1 {
    return json_text_result("invalid line number", true)
  }
  let end = match arguments.get("end") {
    Some(String(s)) if s == "auto" => 0
    Some(Number(value, ..)) => value.to_int()
    _ => start + 20
  }
  let content = @native.read_file(file) catch {
    _ => return json_text_result("failed to read file", true)
  }
  let lines = split_lines_keep_empty(content)
  let total = file_total_lines(lines)
  if total == 0 {
    return json_text_result_data(
      "",
      false,
      obj([
        ("file", str(file)),
        ("start", num(0)),
        ("end", num(0)),
        ("content", str("")),
        ("line_count", num(0)),
        ("brief", bool_json(get_bool(arguments, "brief"))),
      ]),
    )
  }
  if start < 1 || start > total {
    return json_text_result("invalid line number", true)
  }
  let brief = get_bool(arguments, "brief")
  let actual_end = if end <= 0 {
    let range_json = tool_func_range(
      Map([("file", str(file)), ("line", num(start))]),
    )
    match range_json {
      Object(root) =>
        match root.get("content") {
          Some(Array(items)) if items.length() > 0 =>
            match items[0] {
              Object(item) =>
                match item.get("_data") {
                  Some(Object(data)) =>
                    get_int(data, "end").unwrap_or(start + 20)
                  _ => start + 20
                }
              _ => start + 20
            }
          _ => start + 20
        }
      _ => start + 20
    }
  } else if end > total {
    total
  } else {
    end
  }
  let rendered = if brief {
    ""
  } else {
    render_line_range(lines, start, actual_end)
  }
  let viewed_code_id = save_view(
    file,
    start,
    actual_end,
    render_line_range(lines, start, actual_end),
  )
  let data_items : Array[(String, Json)] = [
    ("file", str(file)),
    ("start", num(start)),
    ("end", num(actual_end)),
    ("content", str(rendered)),
    ("line_count", num(total)),
    ("brief", bool_json(brief)),
  ]
  if viewed_code_id is Some(id) {
    data_items.push(("viewed_code_id", str(id)))
  }
  json_text_result_data(rendered, false, obj(data_items))
}

///|
fn tool_write(arguments : Map[String, Json]) -> Json {
  let preview = get_bool(arguments, "preview")
  let brief = get_bool(arguments, "brief")
  let raw = get_bool(arguments, "raw")
  let files_result : Array[Json] = []
  let chip_ids : Array[Json] = []
  let event_ids : Array[Json] = []
  let mut files_count = 0
  match arguments.get("files") {
    Some(Array(items)) if items.length() > 0 =>
      for item in items {
        match item {
          Object(file_item) => {
            let file_opt = get_string(file_item, "file")
            let content_opt = get_string(file_item, "content")
            if file_opt is None || content_opt is None {
              return json_text_result("invalid files entry", true)
            }
            let file = file_opt.unwrap()
            let content = decode_raw_content(content_opt.unwrap(), raw)
            let before_content = @native.read_file(file) catch { _ => "" }
            if !preview {
              @native.write_file(file, content) catch {
                _ => return json_text_result("failed to write file", true)
              }
            }
            files_count += 1
            files_result.push(
              obj([("file", str(file)), ("bytes", num(content.length()))]),
            )
            match save_chip(content) {
              Some(id) => chip_ids.push(str(id))
              None => ()
            }
            if !preview {
              let snapshot = push_snapshot(
                "be-write",
                file,
                before_content,
                content,
                "be-write on \{file}",
              )
              event_ids.push(str(snapshot.id))
              if snapshot.warning != "" {
                files_result.push(obj([("queue_full", str(snapshot.warning))]))
              }
            }
          }
          _ => return json_text_result("invalid files entry", true)
        }
      }
    _ => {
      let file_opt = get_string(arguments, "file")
      let content_opt = get_string(arguments, "content")
      if file_opt is None {
        return json_text_result("missing string field `file`", true)
      }
      if content_opt is None {
        return json_text_result("missing string field `content`", true)
      }
      let file = file_opt.unwrap()
      let content = decode_raw_content(content_opt.unwrap(), raw)
      let before_content = @native.read_file(file) catch { _ => "" }
      if !preview {
        @native.write_file(file, content) catch {
          _ => return json_text_result("failed to write file", true)
        }
      }
      files_count = 1
      files_result.push(
        obj([("file", str(file)), ("bytes", num(content.length()))]),
      )
      match save_chip(content) {
        Some(id) => chip_ids.push(str(id))
        None => ()
      }
      if !preview {
        let snapshot = push_snapshot(
          "be-write",
          file,
          before_content,
          content,
          "be-write on \{file}",
        )
        event_ids.push(str(snapshot.id))
        if snapshot.warning != "" {
          files_result.push(obj([("queue_full", str(snapshot.warning))]))
        }
      }
    }
  }
  let data_items : Array[(String, Json)] = [
    ("ok", bool_json(true)),
    ("files", num(files_count)),
    ("preview", bool_json(preview)),
    ("brief", bool_json(brief)),
  ]
  if !brief {
    data_items.push(("results", arr(files_result)))
  }
  if !chip_ids.is_empty() {
    data_items.push(("chip_ids", arr(chip_ids)))
  }
  if !event_ids.is_empty() {
    data_items.push(("event_ids", arr(event_ids)))
    data_items.push(("event_id", event_ids[event_ids.length() - 1]))
  }
  json_text_result_data(obj(data_items).stringify(), false, obj(data_items))
}

///|
fn tool_replace(arguments : Map[String, Json]) -> Json {
  let file_opt = get_string(arguments, "file")
  let start_opt = match get_int(arguments, "start") {
    Some(value) => Some(value)
    None => get_int(arguments, "start_line")
  }
  let end_opt = match get_int(arguments, "end") {
    Some(value) => Some(value)
    None => get_int(arguments, "end_line")
  }
  let content_opt = match get_string(arguments, "content") {
    Some(content) =>
      Some(decode_raw_content(content, get_bool(arguments, "raw")))
    None => None
  }
  let viewed_code_id_opt = get_string(arguments, "viewed_code_id")
  let old_text_opt = match get_string(arguments, "old") {
    Some(value) => Some(value)
    None => get_string(arguments, "old_text")
  }
  if file_opt is None {
    return json_text_result("missing string field `file`", true)
  }
  if start_opt is None {
    return json_text_result("missing integer field `start`", true)
  }
  if end_opt is None {
    return json_text_result("missing integer field `end`", true)
  }
  if content_opt is None {
    return json_text_result("missing string field `content`", true)
  }
  let file = file_opt.unwrap()
  let start = start_opt.unwrap()
  let end = end_opt.unwrap()
  let content = content_opt.unwrap()
  let preview = get_bool(arguments, "preview")
  let brief = get_bool(arguments, "brief")
  let original = @native.read_file(file) catch {
    _ => return json_text_result("failed to read file", true)
  }
  let old_lines = split_lines_keep_empty(original)
  let total = file_total_lines(old_lines)
  if start < 1 || end < start || end > total + 1 {
    return json_text_result("invalid line range", true)
  }
  if viewed_code_id_opt is Some(view_id) {
    match read_view(view_id) {
      Some((saved_file, saved_start, saved_end, saved_content)) => {
        if saved_file != file || saved_start != start || saved_end != end {
          return json_text_result(
            "viewed_code_id does not match file or range", true,
          )
        }
        let current_content = render_line_range(old_lines, start, end)
        if current_content != saved_content {
          return json_text_result("viewed_code_id content mismatch", true)
        }
      }
      None => return json_text_result("invalid viewed_code_id", true)
    }
  }
  if old_text_opt is Some(old_text) {
    let current = normalized_line_block(line_block(old_lines, start, end))
    let expected = normalized_line_block(
      decode_raw_content(old_text, get_bool(arguments, "raw")),
    )
    if current != expected {
      return json_text_result("old content does not match", true)
    }
  }
  let new_lines = split_lines_keep_empty(content)
  let out : Array[String] = []
  for i in 0..<old_lines.length() {
    let line_no = i + 1
    if line_no == start {
      for new_line in new_lines {
        out.push(new_line)
      }
    }
    if line_no < start || line_no > end {
      out.push(old_lines[i])
    }
  }
  if start == old_lines.length() + 1 {
    for new_line in new_lines {
      out.push(new_line)
    }
  }
  if !preview {
    @native.write_file(file, join_lines(out)) catch {
      _ => return json_text_result("failed to write file", true)
    }
  }
  let after_content = join_lines(out)
  let chip_id = if preview { None } else { save_chip(content) }
  let data_items : Array[(String, Json)] = [
    ("ok", bool_json(true)),
    ("file", str(file)),
    ("start", num(start)),
    ("end", num(end)),
    ("preview", bool_json(preview)),
    ("brief", bool_json(brief)),
    ("removed", num(end - start + 1)),
    ("added", num(file_total_lines(new_lines))),
  ]
  if !preview {
    let snapshot = push_snapshot(
      "be-replace",
      file,
      original,
      after_content,
      "be-replace on \{file} lines \{start}-\{end}",
    )
    data_items.push(("event_id", str(snapshot.id)))
    if snapshot.warning != "" {
      data_items.push(("queue_full", str(snapshot.warning)))
    }
  }
  if viewed_code_id_opt is Some(id) {
    data_items.push(("viewed_code_id", str(id)))
  }
  if chip_id is Some(id) {
    data_items.push(("chip_id", str(id)))
  }
  let payload = obj(data_items)
  json_text_result_data(payload.stringify(), false, payload)
}

///|
fn tool_insert(arguments : Map[String, Json]) -> Json {
  let file_opt = get_string(arguments, "file")
  let after_line_opt = match get_int(arguments, "after_line") {
    Some(value) => Some(value)
    None => get_int(arguments, "line")
  }
  let content_opt = match get_string(arguments, "content") {
    Some(content) =>
      Some(decode_raw_content(content, get_bool(arguments, "raw")))
    None => None
  }
  if file_opt is None {
    return json_text_result("missing string field `file`", true)
  }
  if after_line_opt is None {
    return json_text_result("missing integer field `after_line`", true)
  }
  if content_opt is None {
    return json_text_result("missing string field `content`", true)
  }
  let file = file_opt.unwrap()
  let after_line = after_line_opt.unwrap()
  let preview = get_bool(arguments, "preview")
  let brief = get_bool(arguments, "brief")
  let original = @native.read_file(file) catch {
    _ => return json_text_result("failed to read file", true)
  }
  let old_lines = split_lines_keep_empty(original)
  if after_line < 0 || after_line > old_lines.length() {
    return json_text_result("invalid insertion line", true)
  }
  let insert_lines = split_lines_keep_empty(content_opt.unwrap())
  let out : Array[String] = []
  if after_line == 0 {
    for new_line in insert_lines {
      out.push(new_line)
    }
  }
  for i in 0..<old_lines.length() {
    out.push(old_lines[i])
    if i + 1 == after_line {
      for new_line in insert_lines {
        out.push(new_line)
      }
    }
  }
  if !preview {
    @native.write_file(file, join_lines(out)) catch {
      _ => return json_text_result("failed to write file", true)
    }
  }
  let after_content = join_lines(out)
  let chip_id = if preview { None } else { save_chip(content_opt.unwrap()) }
  let data_items : Array[(String, Json)] = [
    ("ok", bool_json(true)),
    ("file", str(file)),
    ("after_line", num(after_line)),
    ("preview", bool_json(preview)),
    ("brief", bool_json(brief)),
    ("added", num(file_total_lines(insert_lines))),
  ]
  if !preview {
    let snapshot = push_snapshot(
      "be-insert",
      file,
      original,
      after_content,
      "be-insert on \{file} after line \{after_line}",
    )
    data_items.push(("event_id", str(snapshot.id)))
    if snapshot.warning != "" {
      data_items.push(("queue_full", str(snapshot.warning)))
    }
  }
  if chip_id is Some(id) {
    data_items.push(("chip_id", str(id)))
  }
  let payload = obj(data_items)
  json_text_result_data(payload.stringify(), false, payload)
}

///|
fn tool_delete(arguments : Map[String, Json]) -> Json {
  let file_opt = get_string(arguments, "file")
  let start_opt = match get_int(arguments, "start") {
    Some(value) => Some(value)
    None => get_int(arguments, "start_line")
  }
  if file_opt is None {
    return json_text_result("missing string field `file`", true)
  }
  if start_opt is None {
    return json_text_result("missing integer field `start`", true)
  }
  let file = file_opt.unwrap()
  let start = start_opt.unwrap()
  let end = match get_int(arguments, "end") {
    Some(value) => value
    None =>
      match get_int(arguments, "end_line") {
        Some(value) => value
        None => start
      }
  }
  let preview = get_bool(arguments, "preview")
  let brief = get_bool(arguments, "brief")
  let original = @native.read_file(file) catch {
    _ => return json_text_result("failed to read file", true)
  }
  let old_lines = split_lines_keep_empty(original)
  if start < 1 || end < start || end > old_lines.length() {
    return json_text_result("invalid delete range", true)
  }
  let out : Array[String] = []
  for i in 0..<old_lines.length() {
    let line_no = i + 1
    if line_no < start || line_no > end {
      out.push(old_lines[i])
    }
  }
  if !preview {
    @native.write_file(file, join_lines(out)) catch {
      _ => return json_text_result("failed to write file", true)
    }
  }
  let after_content = join_lines(out)
  let payload_items : Array[(String, Json)] = [
    ("ok", bool_json(true)),
    ("file", str(file)),
    ("start", num(start)),
    ("end", num(end)),
    ("preview", bool_json(preview)),
    ("brief", bool_json(brief)),
    ("removed", num(end - start + 1)),
  ]
  if !preview {
    let snapshot = push_snapshot(
      "be-delete",
      file,
      original,
      after_content,
      "be-delete on \{file} lines \{start}-\{end}",
    )
    payload_items.push(("event_id", str(snapshot.id)))
    if snapshot.warning != "" {
      payload_items.push(("queue_full", str(snapshot.warning)))
    }
  }
  let next_payload = obj(payload_items)
  json_text_result_data(next_payload.stringify(), false, next_payload)
}

///|
fn tool_batch(arguments : Map[String, Json]) -> Json {
  let spec_opt = get_string(arguments, "spec")
  if spec_opt is None {
    return json_text_result("missing string field `spec`", true)
  }
  let preview = get_bool(arguments, "preview")
  let brief = get_bool(arguments, "brief")
  let grouped = match parse_batch_spec(spec_opt.unwrap()) {
    Some(value) => value
    None => return json_text_result("invalid batch spec", true)
  }
  let file_results : Array[Json] = []
  let event_ids : Array[Json] = []
  let mut total_edits = 0
  for group in grouped {
    let file = group.0
    let edits0 = group.1
    let original = @native.read_file(file) catch {
      _ => return json_text_result("failed to read file", true)
    }
    let lines0 = split_lines_keep_empty(original)
    let total = file_total_lines(lines0)
    let mut working = lines0.copy()
    let edits = sort_batch_edits_desc(edits0)
    for edit in edits {
      let action = edit.0
      let start = edit.1
      let end = edit.2
      let content = edit.3
      total_edits += 1
      match action {
        "replace-lines" => {
          if start < 1 || end < start || end > file_total_lines(working) + 1 {
            return json_text_result("invalid batch replace range", true)
          }
          let new_lines = split_lines_keep_empty(content)
          let out : Array[String] = []
          for i in 0..<working.length() {
            let line_no = i + 1
            if line_no == start {
              for new_line in new_lines {
                out.push(new_line)
              }
            }
            if line_no < start || line_no > end {
              out.push(working[i])
            }
          }
          if start == working.length() + 1 {
            for new_line in new_lines {
              out.push(new_line)
            }
          }
          working = out
        }
        "insert-after" => {
          if start < 0 || start > file_total_lines(working) {
            return json_text_result("invalid batch insert line", true)
          }
          let insert_lines = split_lines_keep_empty(content)
          let out : Array[String] = []
          if start == 0 {
            for new_line in insert_lines {
              out.push(new_line)
            }
          }
          for i in 0..<working.length() {
            out.push(working[i])
            if i + 1 == start {
              for new_line in insert_lines {
                out.push(new_line)
              }
            }
          }
          working = out
        }
        "delete-lines" => {
          if start < 1 || end < start || end > file_total_lines(working) {
            return json_text_result("invalid batch delete range", true)
          }
          let out : Array[String] = []
          for i in 0..<working.length() {
            let line_no = i + 1
            if line_no < start || line_no > end {
              out.push(working[i])
            }
          }
          working = out
        }
        _ => return json_text_result("unsupported batch action", true)
      }
    }
    let final_content = join_lines(working)
    if !preview {
      @native.write_file(file, final_content) catch {
        _ => return json_text_result("failed to write file", true)
      }
      let snapshot = push_snapshot(
        "be-batch",
        file,
        original,
        final_content,
        "be-batch on \{file}",
      )
      event_ids.push(str(snapshot.id))
    }
    file_results.push(
      obj([
        ("file", str(file)),
        ("before_lines", num(total)),
        ("after_lines", num(file_total_lines(working))),
        ("edits", num(edits.length())),
      ]),
    )
  }
  let payload_items : Array[(String, Json)] = [
    ("ok", bool_json(true)),
    ("files", num(grouped.length())),
    ("edits", num(total_edits)),
    ("preview", bool_json(preview)),
    ("brief", bool_json(brief)),
    ("results", arr(file_results)),
  ]
  if !event_ids.is_empty() {
    payload_items.push(("event_ids", arr(event_ids)))
    payload_items.push(("event_id", event_ids[event_ids.length() - 1]))
  }
  let next_payload = obj(payload_items)
  json_text_result_data(next_payload.stringify(), false, next_payload)
}

///|
fn tool_trx_commit(_arguments : Map[String, Json]) -> Json {
  let count = commit_snapshots()
  let payload = obj([("ok", bool_json(true)), ("committed", num(count))])
  json_text_result_data(payload.stringify(), false, payload)
}

///|
fn tool_trx_rollback(arguments : Map[String, Json]) -> Json {
  let step = get_int(arguments, "step").unwrap_or(1)
  let result = rollback_snapshots(step)
  let count = result.0
  let errors = result.1
  let payload_items : Array[(String, Json)] = [
    ("ok", bool_json(errors.is_empty())),
    ("rolled_back", num(count)),
    ("requested", num(step)),
  ]
  if !errors.is_empty() {
    payload_items.push(("errors", arr(errors.map(err => str(err)))))
  }
  let payload = obj(payload_items)
  json_text_result_data(payload.stringify(), errors.length() > 0, payload)
}

///|
fn tool_trx_status(_arguments : Map[String, Json]) -> Json {
  let snapshots = collect_snapshots()
  let snapshot_items : Array[Json] = []
  let mut mem_bytes = 0
  for snapshot in snapshots {
    mem_bytes +=
      snapshot.before_content.length() + snapshot.after_content.length() +
      snapshot.summary.length()
    snapshot_items.push(
      obj([
        ("id", str(snapshot.id)),
        ("tool", str(snapshot.tool)),
        ("file", str(snapshot.file)),
        ("summary", str(snapshot.summary)),
        ("created_at", str(snapshot.created_at)),
      ]),
    )
  }
  let payload = obj([
    ("ok", bool_json(true)),
    (
      "queue",
      obj([
        ("used", num(snapshots.length())),
        ("max", num(MAX_SNAPSHOTS)),
        ("mem_bytes", num(mem_bytes)),
      ]),
    ),
    ("snapshots", arr(snapshot_items)),
  ])
  json_text_result_data(payload.stringify(), false, payload)
}

///|
fn brace_delta(line : String) -> Int {
  let mut delta = 0
  for ch in line {
    if ch == '{' {
      delta += 1
    } else if ch == '}' {
      delta -= 1
    }
  }
  delta
}

///|
fn tool_func_range(arguments : Map[String, Json]) -> Json {
  let file_opt = get_string(arguments, "file")
  let line_opt = get_int(arguments, "line")
  if file_opt is None {
    return json_text_result("missing string field `file`", true)
  }
  if line_opt is None {
    return json_text_result("missing integer field `line`", true)
  }
  let file = file_opt.unwrap()
  let target_line = line_opt.unwrap()
  let content = @native.read_file(file) catch {
    _ => return json_text_result("failed to read file", true)
  }
  let lines = split_lines_keep_empty(content)
  if target_line < 1 || target_line > lines.length() {
    return json_text_result("invalid line number", true)
  }
  let mut start = target_line
  while start > 1 && !lines[start - 1].contains("{") {
    start -= 1
  }
  if start > 1 &&
    !lines[start - 1].contains("{") &&
    lines[start - 2].contains("{") {
    start -= 1
  }
  let mut depth = 0
  let mut seen_open = false
  let mut end = target_line
  for i in start..<(lines.length() + 1) {
    let line = lines[i - 1]
    if line.contains("{") {
      seen_open = true
    }
    depth += brace_delta(line)
    end = i
    if seen_open && depth <= 0 {
      break
    }
  }
  if end == lines.length() && end > 1 && lines[end - 1] == "" {
    end -= 1
  }
  json_text_result(
    obj([("start", num(start)), ("end", num(end))]).stringify(),
    false,
  )
}

///|
fn matches_pair(opening : Char, closing : Char) -> Bool {
  (opening == '(' && closing == ')') ||
  (opening == '[' && closing == ']') ||
  (opening == '{' && closing == '}')
}

///|
fn tool_balance(arguments : Map[String, Json]) -> Json {
  let file_opt = get_string(arguments, "file")
  if file_opt is None {
    return json_text_result("missing string field `file`", true)
  }
  let content = @native.read_file(file_opt.unwrap()) catch {
    _ => return json_text_result("failed to read file", true)
  }
  let stack : Array[Char] = []
  let issues : Array[String] = []
  let mut in_single = false
  let mut in_double = false
  for ch in content {
    if ch == '"' && !in_single {
      in_double = !in_double
      continue
    }
    if ch == '\'' && !in_double {
      in_single = !in_single
      continue
    }
    if in_single || in_double {
      continue
    }
    if ch == '(' || ch == '[' || ch == '{' {
      stack.push(ch)
    } else if ch == ')' || ch == ']' || ch == '}' {
      if stack.is_empty() {
        issues.push("extra closing \{ch}")
      } else {
        let top = stack.pop().unwrap()
        if !matches_pair(top, ch) {
          issues.push("mismatched pair \{top.to_string()} .. \{ch.to_string()}")
        }
      }
    }
  }
  if in_single {
    issues.push("unclosed single quote")
  }
  if in_double {
    issues.push("unclosed double quote")
  }
  for ch in stack {
    issues.push("unclosed \{ch}")
  }
  if issues.is_empty() {
    json_text_result("balanced", false)
  } else {
    json_text_result(issues.join("\n"), false)
  }
}

///|
fn parse_to_target(target : String) -> (String, Int)? {
  if !target.has_prefix("file://") {
    return None
  }
  let body = target[7:].to_owned()
  match body.split_once(":") {
    Some((file, line_text)) =>
      Some(
        (
          file.to_owned(),
          @strconv.from_str(line_text) catch {
            _ => return None
          },
        ),
      )
    None => None
  }
}

///|
fn tool_insert_chip(arguments : Map[String, Json]) -> Json {
  let from_opt = get_string(arguments, "from")
  let to_opt = get_string(arguments, "to")
  if from_opt is None {
    let ids = list_chip_ids()
    return json_text_result_data(
      ids.join("\n"),
      false,
      obj([("chips", arr(ids.map(id => str(id))))]),
    )
  }
  if to_opt is None {
    return json_text_result("`to` is required", true)
  }
  let from_uri = from_opt.unwrap()
  let target = to_opt.unwrap()
  let source_content = if from_uri.has_prefix("file://") {
    let source_path = from_uri[7:].to_owned()
    @native.read_file(source_path) catch {
      _ => return json_text_result("failed to read source file", true)
    }
  } else if from_uri.has_prefix("chip://") {
    let chip_id = from_uri[7:].to_owned()
    match read_chip(chip_id) {
      Some(content) => content
      None => return json_text_result("failed to read chip", true)
    }
  } else {
    return json_text_result("only file:// or chip:// source is supported", true)
  }
  let inserted = match parse_to_target(target) {
    Some((file, after_line)) =>
      tool_insert(
        Map([
          ("file", str(file)),
          ("after_line", num(after_line)),
          ("content", str(source_content)),
        ]),
      )
    None => json_text_result("invalid `to` target", true)
  }
  inserted
}

///|
fn tool_tag_range(arguments : Map[String, Json]) -> Json {
  let file_opt = get_string(arguments, "file")
  let line_opt = get_int(arguments, "line")
  if file_opt is None {
    return json_text_result("missing string field `file`", true)
  }
  if line_opt is None {
    return json_text_result("missing integer field `line`", true)
  }
  let content = @native.read_file(file_opt.unwrap()) catch {
    _ => return json_text_result("failed to read file", true)
  }
  let lines = split_lines_keep_empty(content)
  let line_no = line_opt.unwrap()
  if line_no < 1 || line_no > lines.length() {
    return json_text_result("invalid line number", true)
  }
  let mut start = line_no
  let mut tag_name : String? = None
  while start >= 1 {
    let line = lines[start - 1]
    match tag_name_from_line(line) {
      Some(name) => {
        tag_name = Some(name)
        break
      }
      None => start -= 1
    }
  }
  if tag_name is None {
    return json_text_result("no opening tag found", true)
  }
  let name = tag_name.unwrap()
  let close_pat = closing_tag(name)
  let mut end = start
  while end <= lines.length() {
    if lines[end - 1].contains(close_pat) {
      break
    }
    end += 1
  }
  if end > lines.length() {
    end = lines.length()
  }
  json_text_result_data(
    obj([("start", num(start)), ("end", num(end)), ("tag", str(name))]).stringify(),
    false,
    obj([("start", num(start)), ("end", num(end)), ("tag", str(name))]),
  )
}

///|
fn tag_name_from_line(line : String) -> String? {
  let trimmed = line.trim()
  if !trimmed.has_prefix("<") || trimmed.has_prefix("</") {
    return None
  }
  let body = trimmed[1:].to_owned()
  let mut name = ""
  for ch in body {
    if ch == ' ' || ch == '>' || ch == '/' {
      break
    }
    name += ch.to_string()
  }
  if name == "" {
    None
  } else {
    Some(name)
  }
}

///|
fn closing_tag(name : String) -> String {
  "</\{name}>"
}

///|
fn tool_call(name : String, arguments : Map[String, Json]) -> Json {
  match name {
    "be-read" => tool_read(arguments)
    "be-write" => tool_write(arguments)
    "be-replace" => tool_replace(arguments)
    "be-insert" => tool_insert(arguments)
    "be-delete" => tool_delete(arguments)
    "be-batch" => tool_batch(arguments)
    "be-func-range" => tool_func_range(arguments)
    "be-balance" => tool_balance(arguments)
    "be-tag-range" => tool_tag_range(arguments)
    "be-insert-chip" => tool_insert_chip(arguments)
    "be-trx-commit" => tool_trx_commit(arguments)
    "be-trx-rollback" => tool_trx_rollback(arguments)
    "be-trx-status" => tool_trx_status(arguments)
    _ => json_text_result("unknown tool: \{name}", true)
  }
}

///|
fn extract_arguments(params : Map[String, Json]) -> Map[String, Json] {
  match params.get("arguments") {
    Some(Object(obj_value)) => obj_value
    _ =>
      match params.get("args") {
        Some(Object(obj_value)) => obj_value
        _ => Map::default()
      }
  }
}

///|
fn handle_request(line : String) -> Json? {
  let req = @json.parse(line) catch {
    _ => return Some(json_error(-32700, "invalid JSON"))
  }
  match req {
    Object(root) => {
      let id = root.get("id").unwrap_or(Json::null())
      let method_opt = get_string(root, "method")
      if method_opt is None {
        return Some(json_error(-32600, "missing method", id~))
      }
      let method_name = method_opt.unwrap()
      match method_name {
        "initialize" =>
          Some(
            json_ok(
              id,
              obj([
                ("protocolVersion", str("2024-11-05")),
                (
                  "serverInfo",
                  obj([
                    ("name", str("better-edit-tools")),
                    ("version", str(VERSION)),
                  ]),
                ),
                (
                  "capabilities",
                  obj([("tools", obj([("listChanged", bool_json(false))]))]),
                ),
              ]),
            ),
          )
        "notifications/initialized" => None
        "tools/list" => Some(json_ok(id, list_tools_result()))
        "tools/call" =>
          match root.get("params") {
            Some(Object(params)) =>
              match get_string(params, "name") {
                Some(name) =>
                  Some(json_ok(id, tool_call(name, extract_arguments(params))))
                None => Some(json_error(-32602, "missing tool name", id~))
              }
            _ => Some(json_error(-32602, "missing params object", id~))
          }
        _ => Some(json_error(-32601, "method not found", id~))
      }
    }
    _ => Some(json_error(-32600, "request must be an object"))
  }
}

///|
pub fn run_main() -> Unit {
  if !handle_cli() {
    return
  }
  for ;; {
    match @native.read_stdin_line() {
      Some(line) => {
        let trimmed = line.trim().to_owned()
        if trimmed == "" {
          continue
        }
        match handle_request(trimmed) {
          Some(response) => println(response.stringify())
          None => ()
        }
      }
      None => break
    }
  }
}
