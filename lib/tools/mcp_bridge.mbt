///|
pub suberror ToolError {
  Failure(message~ : String)
}

///|
fn shell_quote(input : String) -> String {
  "'\{input.replace(old="'", new="'\"'\"'")}'"
}

///|
fn resolve_command_path(command : String) -> String {
  if command == "" || command.has_prefix("/") {
    command
  } else if command.has_prefix("./") {
    let cwd = @env.current_dir().unwrap_or(".")
    "\{cwd}/\{command[2:command.length()]}"
  } else if command.has_prefix("../") || command.contains("/") {
    let cwd = @env.current_dir().unwrap_or(".")
    "\{cwd}/\{command}"
  } else {
    command
  }
}

///|
fn command_string(cfg : @config.ToolsConfig, workdir : String) -> String {
  let args_joined = cfg.better_edit_tools_args.join(" ")
  let command_path = resolve_command_path(cfg.better_edit_tools_cmd)
  let tool_command = if args_joined == "" {
    shell_quote(command_path)
  } else {
    "\{shell_quote(command_path)} \{args_joined}"
  }
  if workdir == "" || workdir == "." {
    tool_command
  } else {
    "cd \{shell_quote(workdir)} && \{tool_command}"
  }
}

///|
fn run_mcp(
  cfg : @config.ToolsConfig,
  workdir : String,
  input : String,
) -> String raise ToolError {
  @native.run_command(command_string(cfg, workdir), stdin_data=input) catch {
    _ => raise ToolError::Failure(message="failed to execute better-edit-tools")
  }
}

///|
fn get_field(obj : Map[String, Json], key : String) -> Json raise ToolError {
  match obj.get(key) {
    Some(value) => value
    None => raise ToolError::Failure(message="missing field: \{key}")
  }
}

///|
fn get_string(obj : Map[String, Json], key : String) -> String? {
  match obj.get(key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn render_tool_content(item : Map[String, Json]) -> String {
  let text = match item.get("text") {
    Some(String(s)) => s
    _ => ""
  }
  match item.get("_data") {
    Some(data) => {
      let data_text = data.stringify()
      if text == "" {
        data_text
      } else if text == data_text {
        text
      } else {
        "\{text}\n\nmetadata:\n\{data_text}"
      }
    }
    None => text
  }
}

///|
fn parse_tool_result(raw : String) -> @model.ToolResult raise ToolError {
  let lines = raw
    .split("\n")
    .filter(line => line != "" && line.has_prefix("{"))
    .map(line => line.to_owned())
    .to_array()
  if lines.is_empty() {
    raise ToolError::Failure(message="empty tool response")
  }
  let payload = @json.parse(lines[lines.length() - 1]) catch {
    _ => raise ToolError::Failure(message="invalid tool response JSON")
  }
  match payload {
    Object(root) =>
      match get_field(root, "result") {
        Object(result) => {
          let text = match result.get("content") {
            Some(Array(items)) if items.length() > 0 =>
              match items[0] {
                Object(item) => render_tool_content(item)
                _ => ""
              }
            _ => ""
          }
          let is_error = match result.get("isError") {
            Some(True) => true
            _ => false
          }
          @model.ToolResult::make("tool-call", text, is_error)
        }
        _ =>
          raise ToolError::Failure(
            message="tool result payload is not an object",
          )
      }
    _ => raise ToolError::Failure(message="tool response root is not an object")
  }
}

///|
fn parse_tool_definitions(
  raw : String,
) -> Array[@model.ToolDef] raise ToolError {
  let lines = raw
    .split("\n")
    .filter(line => line != "" && line.has_prefix("{"))
    .map(line => line.to_owned())
    .to_array()
  if lines.is_empty() {
    raise ToolError::Failure(message="empty tools/list response")
  }
  let payload = @json.parse(lines[lines.length() - 1]) catch {
    _ => raise ToolError::Failure(message="invalid tools/list response JSON")
  }
  match payload {
    Object(root) =>
      match get_field(root, "result") {
        Object(result) =>
          match get_field(result, "tools") {
            Array(items) => {
              let defs : Array[@model.ToolDef] = []
              for item in items {
                match item {
                  Object(tool_obj) => {
                    let name = match get_string(tool_obj, "name") {
                      Some(value) => value
                      None => continue
                    }
                    let description = get_string(tool_obj, "description").unwrap_or(
                      "",
                    )
                    let input_schema = tool_obj
                      .get("inputSchema")
                      .unwrap_or(Json::object(Map::default()))
                    defs.push(
                      @model.ToolDef::make(name, description, input_schema),
                    )
                  }
                  _ => ()
                }
              }
              defs
            }
            _ =>
              raise ToolError::Failure(
                message="tools/list result missing tools array",
              )
          }
        _ =>
          raise ToolError::Failure(
            message="tools/list result payload is not an object",
          )
      }
    _ =>
      raise ToolError::Failure(
        message="tools/list response root is not an object",
      )
  }
}

///|
pub fn fetch_tool_definitions(
  cfg : @config.ToolsConfig,
  workdir : String,
) -> Array[@model.ToolDef] raise ToolError {
  let request = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"moonbit-agent\",\"version\":\"0.1.0\"}}}\n{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}\n{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{}}\n"
  parse_tool_definitions(run_mcp(cfg, workdir, request))
}

///|
pub fn call_tool(
  cfg : @config.ToolsConfig,
  workdir : String,
  name : String,
  arguments_json : String,
) -> @model.ToolResult raise ToolError {
  let request = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"moonbit-agent\",\"version\":\"0.1.0\"}}}\n{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}\n{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\{Json::string(name).stringify()},\"arguments\":\{arguments_json}}}\n"
  parse_tool_result(run_mcp(cfg, workdir, request))
}
