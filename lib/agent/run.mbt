///|
pub suberror AgentError {
  Failure(message~ : String)
}

///|
fn parse_args() -> String {
  let args = @env.args()
  if args.length() >= 3 && args[1] == "--config" {
    args[2]
  } else {
    "agent.toml"
  }
}

///|
fn render_agent_error(err : AgentError) -> String {
  match err {
    Failure(message~) => message
  }
}

///|
fn render_tool_error(err : @tools.ToolError) -> String {
  match err {
    Failure(message~) => message
  }
}

///|
fn render_config_error(err : @config.ConfigError) -> String {
  match err {
    Io(message~) => "io: \{message}"
    Parse(message~) => "parse: \{message}"
    Missing(message~) => "missing: \{message}"
  }
}

///|
fn timestamp_prefix(cfg : @config.AppConfig) -> String {
  if cfg.ui.show_timestamps {
    "[\{@env.now()}] "
  } else {
    ""
  }
}

///|
fn print_ui(cfg : @config.AppConfig, text : String) -> Unit {
  println("\{timestamp_prefix(cfg)}\{text}")
}

///|
fn render_prompt(cfg : @config.AppConfig) -> Unit {
  println("")
  print_ui(cfg, "> ")
}

///|
fn json_quote(raw : String) -> String {
  let builder = StringBuilder::StringBuilder()
  builder.write_string("\"")
  for ch in raw {
    if ch == '"' {
      builder.write_string("\\\"")
    } else if ch == '\\' {
      builder.write_string("\\\\")
    } else if ch == '\n' {
      builder.write_string("\\n")
    } else if ch == '\r' {
      builder.write_string("\\r")
    } else if ch == '\t' {
      builder.write_string("\\t")
    } else if ch.to_int() < 32 {
      builder.write_string(" ")
    } else {
      builder.write_string("\{ch}")
    }
  }
  builder.write_string("\"")
  builder.to_string()
}

///|
fn render_message_json(message : @model.Message) -> String {
  match message {
    System(content) =>
      "{\"role\":\"system\",\"content\":\{json_quote(content)}}"
    User(content) => "{\"role\":\"user\",\"content\":\{json_quote(content)}}"
    Assistant(content) =>
      "{\"role\":\"assistant\",\"content\":\{json_quote(content)}}"
    Tool(call_id~, name~, content~, is_error~) =>
      "{\"role\":\"tool\",\"tool_call_id\":\{json_quote(call_id)},\"name\":\{json_quote(name)},\"content\":\{json_quote(content)},\"is_error\":\{if is_error { "true" } else { "false" }}}"
  }
}

///|
fn render_json_value(value : Json) -> String {
  match value {
    Null => "null"
    True => "true"
    False => "false"
    String(text) => json_quote(text)
    Number(number, repr~) =>
      match repr {
        Some(rendered) => rendered
        None => "\{number}"
      }
    Array(items) => "[\{items.map(render_json_value).join(",")}]"
    Object(entries) => {
      let rendered = entries
        .to_array()
        .map(entry => "\{json_quote(entry.0)}:\{render_json_value(entry.1)}")
        .join(",")
      "{\{rendered}}"
    }
  }
}

///|
fn render_tool_def_json(tool : @model.ToolDef) -> String {
  "{\"type\":\"function\",\"function\":{\"name\":\{json_quote(tool.name)},\"description\":\{json_quote(tool.description)},\"parameters\":\{render_json_value(tool.input_schema)}}}"
}

///|
fn build_request_body(
  cfg : @config.AppConfig,
  messages : Array[@model.Message],
  tools : Array[@model.ToolDef],
) -> String {
  let builder = StringBuilder::StringBuilder()
  builder.write_string("{\"model\":")
  builder.write_string(json_quote(cfg.model.model))
  builder.write_string(",\"temperature\":")
  builder.write_string("\{cfg.model.temperature}")
  builder.write_string(",\"max_tokens\":")
  builder.write_string("\{cfg.model.max_tokens}")
  builder.write_string(",\"messages\":[")
  builder.write_string(messages.map(render_message_json).join(","))
  builder.write_string("],\"tools\":[")
  builder.write_string(tools.map(render_tool_def_json).join(","))
  builder.write_string("]}")
  builder.to_string()
}

///|
fn print_local_help() -> Unit {
  println("local commands:")
  println("  /help                     show local commands")
  println("  /prompt                   show current system prompt")
  println("  /tools                    list MCP tools discovered at startup")
  println(
    "  /toolhelp <tool>          show one discovered MCP tool description",
  )
  println(
    "  /toolschema <tool>        show one discovered MCP tool input schema",
  )
  println("  /history                  show current conversation message count")
  println("  /history full             show current conversation messages")
  println("  /savehistory [path]       write current conversation to text")
  println("  /savehistoryjson [path]   write current conversation to JSONL")
  println("  /loadhistoryjson [path]   load conversation from JSONL")
  println("  /call <tool> <json>       call one MCP tool directly")
  println("  /saveconfig [path]        write current config to toml")
  println(
    "  /clear                    clear conversation history and keep the system prompt",
  )
  println("  /exit                     quit")
}

///|
fn render_tool_names(tools : Array[@model.ToolDef]) -> String {
  if tools.is_empty() {
    "(no tools)"
  } else {
    tools.map(tool => tool.name).join(", ")
  }
}

///|
fn parse_local_tool_call(input : String) -> (String, String)? {
  if !input.has_prefix("/call ") {
    return None
  }
  let payload = input[6:input.length()].trim().to_owned()
  match payload.split_once(" ") {
    Some((name, arguments_json)) if name.trim() != "" &&
      arguments_json.trim() != "" =>
      Some((name.trim().to_owned(), arguments_json.trim().to_owned()))
    _ => None
  }
}

///|
fn parse_tool_help_request(input : String) -> String? {
  if !input.has_prefix("/toolhelp ") {
    return None
  }
  let name = input[10:input.length()].trim().to_owned()
  if name == "" {
    None
  } else {
    Some(name)
  }
}

///|
fn parse_tool_schema_request(input : String) -> String? {
  if !input.has_prefix("/toolschema ") {
    return None
  }
  let name = input[12:input.length()].trim().to_owned()
  if name == "" {
    None
  } else {
    Some(name)
  }
}

///|
fn parse_save_config_request(input : String) -> String? {
  if input == "/saveconfig" {
    return Some("agent.saved.toml")
  }
  if !input.has_prefix("/saveconfig ") {
    return None
  }
  let path = input[12:input.length()].trim().to_owned()
  if path == "" {
    Some("agent.saved.toml")
  } else {
    Some(path)
  }
}

///|
fn parse_history_request(input : String) -> String? {
  if input == "/history" {
    Some("count")
  } else if input == "/history full" {
    Some("full")
  } else {
    None
  }
}

///|
fn parse_save_history_request(input : String) -> String? {
  if input == "/savehistory" {
    return Some("agent.history.txt")
  }
  if !input.has_prefix("/savehistory ") {
    return None
  }
  let path = input[13:input.length()].trim().to_owned()
  if path == "" {
    Some("agent.history.txt")
  } else {
    Some(path)
  }
}

///|
fn parse_save_history_json_request(input : String) -> String? {
  if input == "/savehistoryjson" {
    return Some("agent.history.jsonl")
  }
  if !input.has_prefix("/savehistoryjson ") {
    return None
  }
  let path = input[17:input.length()].trim().to_owned()
  if path == "" {
    Some("agent.history.jsonl")
  } else {
    Some(path)
  }
}

///|
fn parse_load_history_json_request(input : String) -> String? {
  if input == "/loadhistoryjson" {
    return Some("agent.history.jsonl")
  }
  if !input.has_prefix("/loadhistoryjson ") {
    return None
  }
  let path = input[17:input.length()].trim().to_owned()
  if path == "" {
    Some("agent.history.jsonl")
  } else {
    Some(path)
  }
}

///|
fn find_tool_definition(
  tools : Array[@model.ToolDef],
  name : String,
) -> @model.ToolDef? {
  for tool in tools {
    if tool.name == name {
      return Some(tool)
    }
  }
  None
}

///|
fn message_role_name(message : @model.Message) -> String {
  match message {
    System(_) => "system"
    User(_) => "user"
    Assistant(_) => "assistant"
    Tool(..) => "tool"
  }
}

///|
fn message_text_preview(message : @model.Message) -> String {
  match message {
    System(content) | User(content) | Assistant(content) => content
    Tool(call_id~, name~, content~, is_error~) =>
      "[call_id=\{call_id} name=\{name} is_error=\{if is_error { "true" } else { "false" }}] \{content}"
  }
}

///|
fn render_history_dump(history : Array[@model.Message]) -> String {
  if history.is_empty() {
    return "(empty history)"
  }
  let lines : Array[String] = []
  for i in 0..<history.length() {
    let message = history[i]
    lines.push(
      "\{i + 1}. \{message_role_name(message)}: \{message_text_preview(message)}",
    )
  }
  lines.join("\n")
}

///|
fn render_history_jsonl(history : Array[@model.Message]) -> String {
  if history.is_empty() {
    return ""
  }
  history.map(render_message_json).join("\n")
}

///|
fn get_json_string(map : Map[String, Json], key : String) -> String? {
  match map.get(key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn get_json_bool(map : Map[String, Json], key : String) -> Bool {
  match map.get(key) {
    Some(True) => true
    _ => false
  }
}

///|
fn parse_history_message_line(line : String) -> @model.Message raise AgentError {
  let json = @json.parse(line) catch {
    err =>
      raise AgentError::Failure(
        message="load history failed: invalid JSON line: \{err.to_string()}",
      )
  }
  match json {
    Object(root) =>
      match get_json_string(root, "role") {
        Some("system") =>
          @model.system_message(get_json_string(root, "content").unwrap_or(""))
        Some("user") =>
          @model.user_message(get_json_string(root, "content").unwrap_or(""))
        Some("assistant") =>
          @model.assistant_message(
            get_json_string(root, "content").unwrap_or(""),
          )
        Some("tool") =>
          @model.tool_message(
            get_json_string(root, "tool_call_id").unwrap_or("tool-call"),
            get_json_string(root, "name").unwrap_or(""),
            get_json_string(root, "content").unwrap_or(""),
            get_json_bool(root, "is_error"),
          )
        Some(role) =>
          raise AgentError::Failure(
            message="load history failed: unsupported role \{role}",
          )
        None =>
          raise AgentError::Failure(
            message="load history failed: missing role field",
          )
      }
    _ =>
      raise AgentError::Failure(
        message="load history failed: JSON line is not an object",
      )
  }
}

///|
fn load_history_json_file(
  path : String,
) -> Array[@model.Message] raise AgentError {
  let content = @native.read_file(path) catch {
    _ =>
      raise AgentError::Failure(
        message="load history failed: failed to read file",
      )
  }
  let history : Array[@model.Message] = []
  for raw_line in content.split("\n") {
    let line = raw_line.trim().to_owned()
    if line == "" {
      continue
    }
    history.push(parse_history_message_line(line))
  }
  history
}

///|
fn handle_local_command(
  input : String,
  cfg : @config.AppConfig,
  tools : Array[@model.ToolDef],
  history : Array[@model.Message],
) -> Array[@model.Message]? raise AgentError {
  match input {
    "/help" => {
      print_local_help()
      Some(history)
    }
    "/prompt" => {
      print_ui(cfg, cfg.agent.system_prompt)
      Some(history)
    }
    "/tools" => {
      print_ui(cfg, "tools: \{render_tool_names(tools)}")
      Some(history)
    }
    _ if parse_history_request(input) is Some(mode) => {
      if mode == "full" {
        print_ui(cfg, render_history_dump(history))
      } else {
        print_ui(cfg, "history messages: \{history.length()}")
      }
      Some(history)
    }
    _ if parse_tool_schema_request(input) is Some(name) => {
      match find_tool_definition(tools, name) {
        Some(tool) => print_ui(cfg, tool.input_schema.stringify())
        None => raise AgentError::Failure(message="unknown tool: \{name}")
      }
      Some(history)
    }
    _ if parse_tool_help_request(input) is Some(name) => {
      match find_tool_definition(tools, name) {
        Some(tool) => print_ui(cfg, "\{tool.name}: \{tool.description}")
        None => raise AgentError::Failure(message="unknown tool: \{name}")
      }
      Some(history)
    }
    _ if parse_save_config_request(input) is Some(path) => {
      @config.save_config(path, cfg) catch {
        err =>
          raise AgentError::Failure(
            message="save config failed: \{render_config_error(err)}",
          )
      }
      print_ui(cfg, "saved config: \{path}")
      Some(history)
    }
    _ if parse_save_history_request(input) is Some(path) => {
      @native.write_file(path, render_history_dump(history)) catch {
        _ =>
          raise AgentError::Failure(
            message="save history failed: failed to write file",
          )
      }
      print_ui(cfg, "saved history: \{path}")
      Some(history)
    }
    _ if parse_save_history_json_request(input) is Some(path) => {
      @native.write_file(path, render_history_jsonl(history)) catch {
        _ =>
          raise AgentError::Failure(
            message="save history json failed: failed to write file",
          )
      }
      print_ui(cfg, "saved history json: \{path}")
      Some(history)
    }
    _ if parse_load_history_json_request(input) is Some(path) => {
      let loaded = load_history_json_file(path)
      print_ui(
        cfg,
        "loaded history json: \{path} (\{loaded.length()} messages)",
      )
      Some(loaded)
    }
    "/clear" => Some([@model.system_message(cfg.agent.system_prompt)])
    _ =>
      match parse_local_tool_call(input) {
        Some((name, arguments_json)) => {
          let _ = @json.parse(arguments_json) catch {
            _ =>
              raise AgentError::Failure(
                message="local tool call requires valid JSON arguments",
              )
          }
          let result = @tools.call_tool(
            cfg.tools,
            cfg.agent.workdir,
            name,
            arguments_json,
          ) catch {
            err =>
              raise AgentError::Failure(
                message="local tool call failed: \{render_tool_error(err)}",
              )
          }
          print_ui(cfg, result.content_text)
          Some(history)
        }
        None => None
      }
  }
}

///|
fn message_content(reply : Map[String, Json]) -> String {
  match reply.get("content") {
    Some(String(s)) => s
    Some(Array(parts)) => {
      let builder = StringBuilder::StringBuilder()
      for part in parts {
        match part {
          Object(obj) =>
            match obj.get("text") {
              Some(String(text)) => builder.write_string(text)
              _ => ()
            }
          _ => ()
        }
      }
      builder.to_string()
    }
    _ => ""
  }
}

///|
fn parse_tool_calls(reply : Map[String, Json]) -> Array[@model.ToolCall] {
  match reply.get("tool_calls") {
    Some(Array(arr)) => {
      let out : Array[@model.ToolCall] = []
      for item in arr {
        match item {
          Object(obj) =>
            match obj.get("function") {
              Some(Object(fn_map)) => {
                let id = match obj.get("id") {
                  Some(String(s)) => s
                  _ => "tool-call"
                }
                let name = match fn_map.get("name") {
                  Some(String(s)) => s
                  _ => ""
                }
                let arguments_text = match fn_map.get("arguments") {
                  Some(String(s)) => s
                  Some(other) => other.stringify()
                  None => "{}"
                }
                out.push(@model.ToolCall::make(id, name, arguments_text))
              }
              _ => ()
            }
          _ => ()
        }
      }
      out
    }
    _ => []
  }
}

///|
fn api_error_message(root : Map[String, Json]) -> String? {
  match root.get("error") {
    Some(Object(err_obj)) =>
      match err_obj.get("message") {
        Some(String(message)) => Some(message)
        _ => Some("request failed")
      }
    _ => None
  }
}

///|
fn parse_model_response(raw : String) -> @model.ModelReply raise AgentError {
  let json = @json.parse(raw) catch {
    err =>
      raise AgentError::Failure(
        message="model returned invalid JSON: \{err.to_string()}",
      )
  }
  match json {
    Object(root) => {
      match api_error_message(root) {
        Some(message) =>
          raise AgentError::Failure(message="model API error: \{message}")
        None => ()
      }
      match root.get("choices") {
        Some(Array(choices)) if choices.length() > 0 =>
          match choices[0] {
            Object(choice) =>
              match choice.get("message") {
                Some(Object(message)) =>
                  @model.ModelReply::make(
                    message_content(message),
                    parse_tool_calls(message),
                  )
                _ => raise AgentError::Failure(message="model message missing")
              }
            _ =>
              raise AgentError::Failure(message="model choice is not an object")
          }
        _ => raise AgentError::Failure(message="model returned no choices")
      }
    }
    _ => raise AgentError::Failure(message="model root is not an object")
  }
}

///|
fn send_model_request(
  cfg : @config.AppConfig,
  messages : Array[@model.Message],
  tools : Array[@model.ToolDef],
) -> @model.ModelReply raise AgentError {
  let body = build_request_body(cfg, messages, tools)
  let raw = @http.post_json(
    cfg.model.base_url + "/chat/completions",
    cfg.model.api_key,
    body,
  ) catch {
    _ => raise AgentError::Failure(message="model request failed")
  }
  parse_model_response(raw)
}

///|
fn run_turn_with_driver(
  cfg : @config.AppConfig,
  tools : Array[@model.ToolDef],
  history : Array[@model.Message],
  user_input : String,
  next_model_reply : (Array[@model.Message], Array[@model.ToolDef]) -> @model.ModelReply raise AgentError,
  next_tool_result : (@model.ToolCall) -> @model.ToolResult raise AgentError,
  show_output : Bool,
) -> Array[@model.Message] raise AgentError {
  let messages = history.copy()
  messages.push(@model.user_message(user_input))
  let mut turn = 0
  let mut tool_calls = 0
  while turn < cfg.agent.max_turns {
    let reply = next_model_reply(messages, tools)
    if show_output && reply.content != "" {
      print_ui(cfg, reply.content)
    }
    if reply.content != "" {
      messages.push(@model.assistant_message(reply.content))
    }
    if reply.tool_calls.is_empty() {
      break
    }
    for call in reply.tool_calls {
      tool_calls += 1
      if tool_calls > cfg.agent.max_tool_calls_per_turn {
        raise AgentError::Failure(message="tool call limit exceeded")
      }
      if cfg.ui.show_tool_calls {
        print_ui(cfg, "[tool] \{call.name} \{call.arguments_json}")
      }
      let result = next_tool_result(call)
      if show_output && cfg.ui.show_raw_tool_results {
        print_ui(cfg, result.content_text)
      }
      messages.push(
        @model.tool_message(
          call.id,
          call.name,
          result.content_text,
          result.is_error,
        ),
      )
    }
    turn += 1
  }
  messages
}

///|
fn run_turn(
  cfg : @config.AppConfig,
  tools : Array[@model.ToolDef],
  history : Array[@model.Message],
  user_input : String,
) -> Array[@model.Message] raise AgentError {
  run_turn_with_driver(
    cfg,
    tools,
    history,
    user_input,
    (messages, tools) => send_model_request(cfg, messages, tools),
    (call) => {
      @tools.call_tool(
        cfg.tools,
        cfg.agent.workdir,
        call.name,
        call.arguments_json,
      ) catch {
        err =>
          raise AgentError::Failure(
            message="tool call failed: \{render_tool_error(err)}",
          )
      }
    },
    true,
  )
}

///|
pub fn run_main() -> Unit {
  let config_path = parse_args()
  let cfg = @config.load_config(config_path) catch {
    err => {
      println("config error: \{render_config_error(err)}")
      return
    }
  }
  let tool_defs = @tools.fetch_tool_definitions(cfg.tools, cfg.agent.workdir) catch {
    err => {
      println("tool init error: \{render_tool_error(err)}")
      return
    }
  }
  print_ui(cfg, "model: \{cfg.model.model}")
  print_ui(cfg, "workdir: \{cfg.agent.workdir}")
  print_ui(cfg, "type /help for local commands")
  let mut history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
  ]
  for ;; {
    render_prompt(cfg)
    match @native.read_stdin_line() {
      Some(line) => {
        let input = line.trim().to_owned()
        if input == "" {
          continue
        }
        if input == "/exit" {
          break
        }
        let local_result = handle_local_command(input, cfg, tool_defs, history) catch {
          err => {
            print_ui(cfg, "agent error: \{render_agent_error(err)}")
            continue
          }
        }
        match local_result {
          Some(next_history) => {
            history = next_history
            continue
          }
          None => ()
        }
        let next_history = run_turn(cfg, tool_defs, history, input) catch {
          err => {
            print_ui(cfg, "agent error: \{render_agent_error(err)}")
            continue
          }
        }
        history = next_history
      }
      None => break
    }
  }
}
