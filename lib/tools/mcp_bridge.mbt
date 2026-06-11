///|
pub suberror ToolError {
  Failure(message~ : String)
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
fn resolve_workdir(workdir : String) -> String {
  if workdir == "" || workdir == "." {
    @env.current_dir().unwrap_or(".")
  } else if workdir.has_prefix("/") {
    workdir
  } else {
    let cwd = @env.current_dir().unwrap_or(".")
    "\{cwd}/\{workdir}"
  }
}

///|
fn shell_quote(input : String) -> String {
  "'\{input.replace(old="'", new="'\"'\"'")}'"
}

///|
fn command_string(cfg : @config.ToolsConfig, workdir : String) -> String {
  let command_path = resolve_command_path(cfg.better_edit_tools_cmd)
  let args = cfg.better_edit_tools_args.map(shell_quote).join(" ")
  let tool_command = if args == "" {
    shell_quote(command_path)
  } else {
    "\{shell_quote(command_path)} \{args}"
  }
  let resolved_workdir = resolve_workdir(workdir)
  "cd \{shell_quote(resolved_workdir)} && \{tool_command}"
}

///|
fn response_lines(output : String) -> Array[String] {
  output
    .split("\n")
    .filter(line => line != "" && line.has_prefix("{"))
    .map(line => line.to_owned())
    .to_array()
}

fn jsonrpc_result_or_error(
  response_str : String,
) -> Result[Json, ToolError] {
  let json = @json.parse(response_str) catch {
    _ => return Err(ToolError::Failure(message="invalid JSON response"))
  }
  match json {
    Object(obj) => {
      match obj.get("error") {
        Some(Object(err_obj)) => {
          let message = match err_obj.get("message") {
            Some(String(m)) => m
            _ => "unknown server error"
          }
          Err(ToolError::Failure(message="server error: \{message}"))
        }
        _ =>
          match obj.get("result") {
            Some(result_json) => Ok(result_json)
            None =>
              Err(
                ToolError::Failure(message="response missing 'result' field"),
              )
          }
      }
    }
    _ => Err(ToolError::Failure(message="response must be a JSON object"))
  }
}

///|
fn parse_tool_definitions_result(
  result_json : Json,
) -> Result[Array[@model.ToolDef], ToolError] {
  match result_json {
    Object(obj) =>
      match obj.get("tools") {
        Some(Array(items)) => {
          let defs : Array[@model.ToolDef] = []
          for item in items {
            match item {
              Object(tool_obj) => {
                let name = match tool_obj.get("name") {
                  Some(String(value)) => value
                  _ => continue
                }
                let description = match tool_obj.get("description") {
                  Some(String(value)) => value
                  _ => ""
                }
                let input_schema = tool_obj.get("inputSchema").unwrap_or(
                  Json::null(),
                )
                defs.push(@model.ToolDef::make(name, description, input_schema))
              }
              _ => ()
            }
          }
          Ok(defs)
        }
        _ => Err(ToolError::Failure(message="tools/list missing tools array"))
      }
    _ => Err(ToolError::Failure(message="tools/list result must be an object"))
  }
}

///|
fn render_content_item(item : Json) -> String? {
  match item {
    Object(obj) =>
      match obj.get("type") {
        Some(String("text")) =>
          match obj.get("text") {
            Some(String(text)) => Some(text)
            _ => None
          }
        Some(String("image")) =>
          match obj.get("mimeType") {
            Some(String(mime_type)) => Some("[image:\{mime_type}]")
            _ => Some("[image:image/png]")
          }
        Some(String("resource_link")) =>
          match obj.get("uri") {
            Some(String(uri)) => Some(uri)
            _ => None
          }
        Some(String("resource")) => {
          let uri = match obj.get("uri") {
            Some(String(value)) => value
            _ => ""
          }
          match obj.get("text") {
            Some(String(text)) => Some("resource:\{uri}\n\{text}")
            _ =>
              match obj.get("blob") {
                Some(String(_)) =>
                  match obj.get("mimeType") {
                    Some(String(mime_type)) =>
                      Some("resource:\{uri} [blob:\{mime_type}]")
                    _ => Some("resource:\{uri} [blob:application/octet-stream]")
                  }
                _ => None
              }
          }
        }
        _ => None
      }
    _ => None
  }
}

///|
fn parse_tool_call_result(
  result_json : Json,
) -> Result[@model.ToolResult, ToolError] {
  match result_json {
    Object(obj) => {
      let text = match obj.get("content") {
        Some(Array(items)) => items.filter_map(render_content_item).join("\n\n")
        _ => ""
      }
      let is_error = match obj.get("isError") {
        Some(True) => true
        _ => false
      }
      Ok(@model.ToolResult::make("tool-call", text, is_error))
    }
    _ => Err(ToolError::Failure(message="tools/call result must be an object"))
  }
}

///|
fn run_mcp_requests(
  cfg : @config.ToolsConfig,
  workdir : String,
  requests : Array[String],
) -> Result[Json, ToolError] {
  let stdin_data = requests.join("\n") + "\n"
  let output = @native.run_command(
    command_string(cfg, workdir),
    stdin_data=stdin_data,
  ) catch {
    _ =>
      return Err(
        ToolError::Failure(
          message="failed to execute better-edit-tools",
        ),
      )
  }
  let lines = response_lines(output)
  if lines.is_empty() {
    return Err(ToolError::Failure(message="empty MCP response"))
  }
  jsonrpc_result_or_error(lines[lines.length() - 1])
}

///|
fn mcp_initialize_request() -> String {
  @mcp_client.build_initialize_request(
    1,
    "moonbit-agent",
    "0.1.0",
    capabilities={
      roots: None,
      sampling: None,
      elicitation: None,
    },
  )
}

///|
pub fn fetch_tool_definitions(
  cfg : @config.ToolsConfig,
  workdir : String,
) -> Result[Array[@model.ToolDef], ToolError] {
  let result_json = run_mcp_requests(cfg, workdir, [
    mcp_initialize_request(),
    @mcp_client.build_tools_list_request(2),
  ])
  match result_json {
    Ok(value) => parse_tool_definitions_result(value)
    Err(Failure(message~)) =>
      Err(ToolError::Failure(message="tools/list failed: \{message}"))
  }
}

///|
pub fn call_tool(
  cfg : @config.ToolsConfig,
  workdir : String,
  name : String,
  arguments_json : String,
) -> Result[@model.ToolResult, ToolError] {
  let result_json = run_mcp_requests(cfg, workdir, [
    mcp_initialize_request(),
    @mcp_client.build_tools_call_request(2, name, arguments=arguments_json),
  ])
  match result_json {
    Ok(value) => parse_tool_call_result(value)
    Err(Failure(message~)) =>
      Err(ToolError::Failure(message="tools/call failed: \{message}"))
  }
}
