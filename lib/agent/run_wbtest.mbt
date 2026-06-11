///|
fn sample_cfg() -> @config.AppConfig {
  @config.default_config()
}

///|
fn sample_tools() -> Array[@model.ToolDef] {
  [
    @model.ToolDef::make("be-read", "Read file content with line numbers.", {
      "type": "object",
    }),
    @model.ToolDef::make("be-write", "Write full file content.", {
      "type": "object",
    }),
  ]
}

///|
fn scripted_model_driver(
  replies : Array[@model.ModelReply],
) -> (Array[@model.Message], Array[@model.ToolDef]) -> @model.ModelReply raise AgentError {
  let mut reply_index = 0
  (_messages, _tools) => {
    if reply_index >= replies.length() {
      raise AgentError::Failure(message="scripted model reply exhausted")
    }
    let reply = replies[reply_index]
    reply_index += 1
    reply
  }
}

///|
fn scripted_tool_driver(
  results : Array[@model.ToolResult],
) -> (@model.ToolCall) -> @model.ToolResult raise AgentError {
  let mut result_index = 0
  (_call) => {
    if result_index >= results.length() {
      raise AgentError::Failure(message="scripted tool result exhausted")
    }
    let result = results[result_index]
    result_index += 1
    result
  }
}

///|
async fn run_scripted_turn(
  cfg : @config.AppConfig,
  tools : Array[@model.ToolDef],
  history : Array[@model.Message],
  user_input : String,
  replies : Array[@model.ModelReply],
  results : Array[@model.ToolResult],
) -> Result[Array[@model.Message], AgentError] {
  run_turn_with_driver(
    cfg,
    tools,
    history,
    user_input,
    scripted_model_driver(replies),
    (call) => {
      let result = scripted_tool_driver(results)(call) catch {
        err => return Err(err)
      }
      Ok(result)
    },
    false,
  )
}

///|
async fn run_local_command_for_test(
  input : String,
  cfg : @config.AppConfig,
  tools : Array[@model.ToolDef],
  history : Array[@model.Message],
) -> Result[Array[@model.Message]?, AgentError] {
  handle_local_command(input, cfg, tools, history)
}


///|
async test "handle_local_command clears history but preserves system prompt" {
  let cfg = sample_cfg()
  let history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
    @model.user_message("hello"),
    @model.assistant_message("world"),
  ]
  let next_history = match run_local_command_for_test(
    "/clear",
    cfg,
    sample_tools(),
    history,
  ) {
    Ok(Some(value)) => value
    Ok(None) => {
      @debug.assert_eq("some", "none")
      return
    }
    Err(err) => {
      @debug.assert_eq(render_agent_error(err), "__unexpected_error__")
      return
    }
  }
  @debug.assert_eq(next_history.length(), 1)
  match next_history[0] {
    System(content) => @debug.assert_eq(content, cfg.agent.system_prompt)
    _ => @debug.assert_eq("system", "unexpected")
  }
}

///|
test "parse_local_tool_call extracts tool name and json payload" {
  let parsed = parse_local_tool_call(
    "/call be-read {\"file\":\"/tmp/x\",\"start\":1}",
  )
  @debug.assert_eq(parsed is Some(_), true)
  let result = parsed.unwrap()
  @debug.assert_eq(result.0, "be-read")
  @debug.assert_eq(result.1, "{\"file\":\"/tmp/x\",\"start\":1}")
}

///|
test "parse_tool_help_request extracts tool name" {
  @debug.assert_eq(
    parse_tool_help_request("/toolhelp be-read").unwrap(),
    "be-read",
  )
  @debug.assert_eq(parse_tool_help_request("/toolhelp ") is None, true)
}

///|
test "parse_tool_schema_request extracts tool name" {
  @debug.assert_eq(
    parse_tool_schema_request("/toolschema be-read").unwrap(),
    "be-read",
  )
  @debug.assert_eq(parse_tool_schema_request("/toolschema ") is None, true)
}

///|
test "parse_save_config_request uses default path" {
  @debug.assert_eq(
    parse_save_config_request("/saveconfig").unwrap(),
    "agent.saved.toml",
  )
  @debug.assert_eq(
    parse_save_config_request("/saveconfig /tmp/x.toml").unwrap(),
    "/tmp/x.toml",
  )
}

///|
test "parse_history_request parses count and full modes" {
  @debug.assert_eq(parse_history_request("/history").unwrap(), "count")
  @debug.assert_eq(parse_history_request("/history full").unwrap(), "full")
}

///|
test "parse_save_history_request uses default and explicit paths" {
  @debug.assert_eq(
    parse_save_history_request("/savehistory").unwrap(),
    "agent.history.txt",
  )
  @debug.assert_eq(
    parse_save_history_request("/savehistory /tmp/agent-history.txt").unwrap(),
    "/tmp/agent-history.txt",
  )
}

///|
test "parse_save_history_json_request uses default and explicit paths" {
  @debug.assert_eq(
    parse_save_history_json_request("/savehistoryjson").unwrap(),
    "agent.history.jsonl",
  )
  @debug.assert_eq(
    parse_save_history_json_request("/savehistoryjson /tmp/agent-history.jsonl").unwrap(),
    "/tmp/agent-history.jsonl",
  )
}

///|
test "parse_load_history_json_request uses default and explicit paths" {
  @debug.assert_eq(
    parse_load_history_json_request("/loadhistoryjson").unwrap(),
    "agent.history.jsonl",
  )
  @debug.assert_eq(
    parse_load_history_json_request("/loadhistoryjson /tmp/agent-history.jsonl").unwrap(),
    "/tmp/agent-history.jsonl",
  )
}

///|
test "parse_local_tool_call rejects missing payload" {
  @debug.assert_eq(parse_local_tool_call("/call be-read") is None, true)
}

///|
async test "handle_local_command returns unchanged history for tools listing" {
  let cfg = sample_cfg()
  let history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
    @model.user_message("hello"),
  ]
  let next_history = match run_local_command_for_test(
    "/tools",
    cfg,
    sample_tools(),
    history,
  ) {
    Ok(Some(value)) => value
    _ => {
      @debug.assert_eq("ok some", "unexpected")
      return
    }
  }
  @debug.assert_eq(next_history.length(), history.length())
}

///|
test "find_tool_definition finds discovered tool by name" {
  let tool = find_tool_definition(sample_tools(), "be-write").unwrap()
  @debug.assert_eq(tool.description, "Write full file content.")
}

///|
async test "handle_local_command saves config to requested path" {
  let cfg = sample_cfg()
  let history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
  ]
  let path = "/tmp/moon_agent_saved_from_command.toml"
  let next_history = match run_local_command_for_test(
    "/saveconfig /tmp/moon_agent_saved_from_command.toml",
    cfg,
    sample_tools(),
    history,
  ) {
    Ok(Some(value)) => value
    _ => {
      @debug.assert_eq("ok some", "unexpected")
      return
    }
  }
  @debug.assert_eq(next_history.length(), history.length())
  let loaded = @config.load_config(path) catch { _ => @config.default_config() }
  @debug.assert_eq(loaded.agent.system_prompt, cfg.agent.system_prompt)
}

///|
async test "handle_local_command saves history to requested path" {
  let cfg = sample_cfg()
  let history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
    @model.user_message("hello"),
  ]
  let path = "/tmp/moon_agent_saved_history.txt"
  let next_history = match run_local_command_for_test(
    "/savehistory /tmp/moon_agent_saved_history.txt",
    cfg,
    sample_tools(),
    history,
  ) {
    Ok(Some(value)) => value
    _ => {
      @debug.assert_eq("ok some", "unexpected")
      return
    }
  }
  @debug.assert_eq(next_history.length(), history.length())
  let saved = @native.read_file(path) catch { _ => "" }
  @debug.assert_eq(saved.contains("1. system:"), true)
  @debug.assert_eq(saved.contains("2. user: hello"), true)
}

///|
async test "handle_local_command saves history json to requested path" {
  let cfg = sample_cfg()
  let history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
    @model.user_message("hello"),
  ]
  let path = "/tmp/moon_agent_saved_history.jsonl"
  let next_history = match run_local_command_for_test(
    "/savehistoryjson /tmp/moon_agent_saved_history.jsonl",
    cfg,
    sample_tools(),
    history,
  ) {
    Ok(Some(value)) => value
    _ => {
      @debug.assert_eq("ok some", "unexpected")
      return
    }
  }
  @debug.assert_eq(next_history.length(), history.length())
  let saved = @native.read_file(path) catch { _ => "" }
  @debug.assert_eq(saved.contains("\"role\":\"system\""), true)
  @debug.assert_eq(saved.contains("\"role\":\"user\""), true)
  @debug.assert_eq(saved.contains("\"content\":\"hello\""), true)
}

///|
test "parse_history_message_line parses tool messages" {
  let message = parse_history_message_line(
    "{\"role\":\"tool\",\"tool_call_id\":\"call-1\",\"name\":\"be-read\",\"content\":\"ok\",\"is_error\":true}",
  ) catch {
    _ => @model.system_message("unexpected")
  }
  match message {
    Tool(call_id~, name~, content~, is_error~) => {
      @debug.assert_eq(call_id, "call-1")
      @debug.assert_eq(name, "be-read")
      @debug.assert_eq(content, "ok")
      @debug.assert_eq(is_error, true)
    }
    _ => @debug.assert_eq("tool", "unexpected")
  }
}

///|
async test "handle_local_command loads history json from requested path" {
  let cfg = sample_cfg()
  let history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
  ]
  let path = "/tmp/moon_agent_loaded_history.jsonl"
  @native.write_file(
    path, "{\"role\":\"system\",\"content\":\"sys\"}\n{\"role\":\"user\",\"content\":\"hello\"}\n{\"role\":\"tool\",\"tool_call_id\":\"call-2\",\"name\":\"be-read\",\"content\":\"done\",\"is_error\":false}",
  ) catch {
    _ => ()
  }
  let loaded = match run_local_command_for_test(
    "/loadhistoryjson /tmp/moon_agent_loaded_history.jsonl",
    cfg,
    sample_tools(),
    history,
  ) {
    Ok(Some(value)) => value
    Ok(None) => {
      @debug.assert_eq("some", "none")
      return
    }
    Err(err) => {
      @debug.assert_eq(render_agent_error(err), "__unexpected_error__")
      return
    }
  }
  @debug.assert_eq(loaded.length(), 3)
  match loaded[0] {
    System(content) => @debug.assert_eq(content, "sys")
    _ => @debug.assert_eq("system", "unexpected")
  }
  match loaded[1] {
    User(content) => @debug.assert_eq(content, "hello")
    _ => @debug.assert_eq("user", "unexpected")
  }
  match loaded[2] {
    Tool(call_id~, name~, content~, is_error~) => {
      @debug.assert_eq(call_id, "call-2")
      @debug.assert_eq(name, "be-read")
      @debug.assert_eq(content, "done")
      @debug.assert_eq(is_error, false)
    }
    _ => @debug.assert_eq("tool", "unexpected")
  }
}

///|
test "timestamp_prefix follows ui configuration" {
  let cfg = sample_cfg()
  @debug.assert_eq(timestamp_prefix(cfg), "")
}

///|
async test "handle_local_command returns unchanged history for history command" {
  let cfg = sample_cfg()
  let history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
    @model.user_message("hello"),
  ]
  let next_history = match run_local_command_for_test(
    "/history",
    cfg,
    sample_tools(),
    history,
  ) {
    Ok(Some(value)) => value
    Ok(None) => {
      @debug.assert_eq("some", "none")
      return
    }
    Err(err) => {
      @debug.assert_eq(render_agent_error(err), "__unexpected_error__")
      return
    }
  }
  @debug.assert_eq(next_history.length(), history.length())
}

///|
async test "handle_local_command returns unchanged history for prompt command" {
  let cfg = sample_cfg()
  let history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
    @model.user_message("hello"),
  ]
  let next_history = match run_local_command_for_test(
    "/prompt",
    cfg,
    sample_tools(),
    history,
  ) {
    Ok(Some(value)) => value
    Ok(None) => {
      @debug.assert_eq("some", "none")
      return
    }
    Err(err) => {
      @debug.assert_eq(render_agent_error(err), "__unexpected_error__")
      return
    }
  }
  @debug.assert_eq(next_history.length(), history.length())
}

///|
async test "handle_local_command rejects invalid local tool json" {
  let cfg = sample_cfg()
  let history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
  ]
  let result = run_local_command_for_test(
    "/call be-read not-json",
    cfg,
    sample_tools(),
    history,
  )
  match result {
    Err(err) =>
      @debug.assert_eq(
        render_agent_error(err),
        "local tool call requires valid JSON arguments",
      )
    Ok(_) => @debug.assert_eq("error", "expected")
  }
}

///|
test "render_history_dump includes indexed roles and content" {
  let history : Array[@model.Message] = [
    @model.system_message("sys"),
    @model.user_message("hello"),
    @model.assistant_message("world"),
  ]
  let text = render_history_dump(history)
  @debug.assert_eq(text.contains("1. system: sys"), true)
  @debug.assert_eq(text.contains("2. user: hello"), true)
  @debug.assert_eq(text.contains("3. assistant: world"), true)
}

///|
test "render_history_jsonl emits one json object per line" {
  let history : Array[@model.Message] = [
    @model.system_message("sys"),
    @model.user_message("hello"),
  ]
  let text = render_history_jsonl(history)
  @debug.assert_eq(text.contains("\"role\":\"system\""), true)
  @debug.assert_eq(text.contains("\"role\":\"user\""), true)
  @debug.assert_eq(text.contains("\n"), true)
}

///|
async test "handle_local_command rejects unknown tool help target" {
  let cfg = sample_cfg()
  let history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
  ]
  let result = run_local_command_for_test(
    "/toolhelp nope",
    cfg,
    sample_tools(),
    history,
  )
  match result {
    Err(err) => @debug.assert_eq(render_agent_error(err), "unknown tool: nope")
    Ok(_) => @debug.assert_eq("error", "expected")
  }
}

///|
test "render_tool_names joins discovered tools" {
  let names = render_tool_names(sample_tools())
  @debug.assert_eq(names, "be-read, be-write")
}

///|
test "api_error_message extracts error payload message" {
  let payload : Map[String, Json] = { "error": { "message": "bad api key" } }
  @debug.assert_eq(api_error_message(payload).unwrap(), "bad api key")
}

///|
test "build_request_body renders messages and tools without root stringify" {
  let cfg = sample_cfg()
  let tools = [
    @model.ToolDef::make(
      "be-read",
      "Read file content with line numbers.",
      {
        "type": "object",
        "properties": {
          "file": { "type": "string" },
          "start": { "type": "integer" },
        },
        "required": ["file", "start"],
      },
    ),
  ]
  let body = build_request_body(
    cfg,
    [
      @model.system_message(cfg.agent.system_prompt),
      @model.user_message("hello"),
    ],
    tools,
  )
  @debug.assert_eq(body.contains("\"messages\":"), true)
  @debug.assert_eq(body.contains("\"tools\":"), true)
  @debug.assert_eq(body.contains("\"be-read\""), true)
  @debug.assert_eq(body.contains("\"hello\""), true)
  @debug.assert_eq(body.contains("\"start\""), true)
  @debug.assert_eq(body.contains("\"integer\""), true)
  @debug.assert_eq(body.contains("\"required\""), true)
}

///|
test "parse_model_response reads assistant content and tool calls" {
  let raw = "{\"choices\":[{\"message\":{\"content\":\"\",\"tool_calls\":[{\"id\":\"call-1\",\"type\":\"function\",\"function\":{\"name\":\"be-read\",\"arguments\":\"{\\\"file\\\":\\\"/tmp/x\\\",\\\"start\\\":1}\"}}]}}]}"
  let reply = parse_model_response(raw)
  @debug.assert_eq(reply.content, "")
  @debug.assert_eq(reply.tool_calls.length(), 1)
  @debug.assert_eq(reply.tool_calls[0].id, "call-1")
  @debug.assert_eq(reply.tool_calls[0].name, "be-read")
  @debug.assert_eq(
    reply.tool_calls[0].arguments_json.contains("\"file\":\"/tmp/x\""),
    true,
  )
}

///|
async test "run_turn_with_driver completes scripted multi turn tool flow" {
  let cfg = sample_cfg()
  let history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
  ]
  let next_history = match run_scripted_turn(
    cfg,
    sample_tools(),
    history,
    "read file",
    [
      @model.ModelReply::make(
        "",
        [
          @model.ToolCall::make(
            "call-1",
            "be-read",
            "{\"file\":\"/tmp/x\",\"start\":1}",
          ),
        ],
      ),
      @model.ModelReply::make("final answer", []),
    ],
    [@model.ToolResult::make("call-1", "1: alpha", false)],
  ) {
    Ok(value) => value
    Err(err) => {
      @debug.assert_eq(render_agent_error(err), "__unexpected_error__")
      return
    }
  }
  @debug.assert_eq(next_history.length(), 4)
  match next_history[1] {
    User(content) => @debug.assert_eq(content, "read file")
    _ => @debug.assert_eq("user", "unexpected")
  }
  match next_history[2] {
    Tool(call_id~, name~, content~, is_error~) => {
      @debug.assert_eq(call_id, "call-1")
      @debug.assert_eq(name, "be-read")
      @debug.assert_eq(content, "1: alpha")
      @debug.assert_eq(is_error, false)
    }
    _ => @debug.assert_eq("tool", "unexpected")
  }
  match next_history[3] {
    Assistant(content) => @debug.assert_eq(content, "final answer")
    _ => @debug.assert_eq("assistant", "unexpected")
  }
}

///|
async test "run_turn_with_driver reports scripted model exhaustion" {
  let cfg = sample_cfg()
  let history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
  ]
  let result = run_turn_with_driver(
    cfg,
    sample_tools(),
    history,
    "read file",
    (_messages, _tools) => {
      raise AgentError::Failure(message="scripted model reply exhausted")
    },
    (_call) => Ok(@model.ToolResult::make("call-1", "ok", false)),
    false,
  )
  match result {
    Err(err) =>
      @debug.assert_eq(render_agent_error(err), "scripted model reply exhausted")
    Ok(_) => @debug.assert_eq("error", "expected")
  }
}

///|
async test "run_turn_with_driver enforces tool call limit with scripted replies" {
  let cfg = sample_cfg()
  let history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
  ]
  let tool_calls : Array[@model.ToolCall] = []
  let tool_results : Array[@model.ToolResult] = []
  for i in 0..<(cfg.agent.max_tool_calls_per_turn + 1) {
    tool_calls.push(@model.ToolCall::make("call-\{i}", "be-read", "{}"))
    tool_results.push(@model.ToolResult::make("call-\{i}", "ok", false))
  }
  let result = run_scripted_turn(
    cfg,
    sample_tools(),
    history,
    "read file",
    [@model.ModelReply::make("", tool_calls)],
    tool_results,
  )
  match result {
    Err(err) => @debug.assert_eq(render_agent_error(err), "tool call limit exceeded")
    Ok(_) => @debug.assert_eq("error", "expected")
  }
}

///|
async test "run_scripted_turn preserves assistant content before tool call continuation" {
  let cfg = sample_cfg()
  let history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
  ]
  let next_history = match run_scripted_turn(
    cfg,
    sample_tools(),
    history,
    "inspect file",
    [
      @model.ModelReply::make(
        "Let me inspect that.",
        [@model.ToolCall::make("call-1", "be-read", "{\"file\":\"/tmp/x\"}")],
      ),
      @model.ModelReply::make("done", []),
    ],
    [@model.ToolResult::make("call-1", "1: alpha", false)],
  ) {
    Ok(value) => value
    Err(err) => {
      @debug.assert_eq(render_agent_error(err), "__unexpected_error__")
      return
    }
  }
  @debug.assert_eq(next_history.length(), 5)
  match next_history[2] {
    Assistant(content) => @debug.assert_eq(content, "Let me inspect that.")
    _ => @debug.assert_eq("assistant", "unexpected")
  }
  match next_history[4] {
    Assistant(content) => @debug.assert_eq(content, "done")
    _ => @debug.assert_eq("assistant", "unexpected")
  }
}

///|
async test "run_scripted_turn reports scripted tool exhaustion" {
  let cfg = sample_cfg()
  let history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
  ]
  let result = run_scripted_turn(
    cfg,
    sample_tools(),
    history,
    "read file",
    [
      @model.ModelReply::make(
        "",
        [@model.ToolCall::make("call-1", "be-read", "{}")],
      ),
    ],
    [],
  )
  match result {
    Err(err) =>
      @debug.assert_eq(render_agent_error(err), "scripted tool result exhausted")
    Ok(_) => @debug.assert_eq("error", "expected")
  }
}
