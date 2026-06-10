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
test "handle_local_command clears history but preserves system prompt" {
  let cfg = sample_cfg()
  let history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
    @model.user_message("hello"),
    @model.assistant_message("world"),
  ]
  let next_history = handle_local_command(
    "/clear",
    cfg,
    sample_tools(),
    history,
  ) catch {
    _ => None
  }
  @debug.assert_eq(next_history is Some(_), true)
  let cleared = next_history.unwrap()
  @debug.assert_eq(cleared.length(), 1)
  match cleared[0] {
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
test "handle_local_command returns unchanged history for tools listing" {
  let cfg = sample_cfg()
  let history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
    @model.user_message("hello"),
  ]
  let next_history = handle_local_command(
    "/tools",
    cfg,
    sample_tools(),
    history,
  ) catch {
    _ => None
  }
  @debug.assert_eq(next_history is Some(_), true)
  @debug.assert_eq(next_history.unwrap().length(), history.length())
}

///|
test "find_tool_definition finds discovered tool by name" {
  let tool = find_tool_definition(sample_tools(), "be-write").unwrap()
  @debug.assert_eq(tool.description, "Write full file content.")
}

///|
test "handle_local_command saves config to requested path" {
  let cfg = sample_cfg()
  let history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
  ]
  let path = "/tmp/moon_agent_saved_from_command.toml"
  let next_history = handle_local_command(
    "/saveconfig /tmp/moon_agent_saved_from_command.toml",
    cfg,
    sample_tools(),
    history,
  ) catch {
    _ => None
  }
  @debug.assert_eq(next_history is Some(_), true)
  let loaded = @config.load_config(path) catch { _ => @config.default_config() }
  @debug.assert_eq(loaded.agent.system_prompt, cfg.agent.system_prompt)
}

///|
test "handle_local_command saves history to requested path" {
  let cfg = sample_cfg()
  let history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
    @model.user_message("hello"),
  ]
  let path = "/tmp/moon_agent_saved_history.txt"
  let next_history = handle_local_command(
    "/savehistory /tmp/moon_agent_saved_history.txt",
    cfg,
    sample_tools(),
    history,
  ) catch {
    _ => None
  }
  @debug.assert_eq(next_history is Some(_), true)
  let saved = @native.read_file(path) catch { _ => "" }
  @debug.assert_eq(saved.contains("1. system:"), true)
  @debug.assert_eq(saved.contains("2. user: hello"), true)
}

///|
test "handle_local_command saves history json to requested path" {
  let cfg = sample_cfg()
  let history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
    @model.user_message("hello"),
  ]
  let path = "/tmp/moon_agent_saved_history.jsonl"
  let next_history = handle_local_command(
    "/savehistoryjson /tmp/moon_agent_saved_history.jsonl",
    cfg,
    sample_tools(),
    history,
  ) catch {
    _ => None
  }
  @debug.assert_eq(next_history is Some(_), true)
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
test "handle_local_command loads history json from requested path" {
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
  let next_history = handle_local_command(
    "/loadhistoryjson /tmp/moon_agent_loaded_history.jsonl",
    cfg,
    sample_tools(),
    history,
  ) catch {
    _ => None
  }
  @debug.assert_eq(next_history is Some(_), true)
  let loaded = next_history.unwrap()
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
test "handle_local_command returns unchanged history for history command" {
  let cfg = sample_cfg()
  let history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
    @model.user_message("hello"),
  ]
  let next_history = handle_local_command(
    "/history",
    cfg,
    sample_tools(),
    history,
  ) catch {
    _ => None
  }
  @debug.assert_eq(next_history is Some(_), true)
  @debug.assert_eq(next_history.unwrap().length(), history.length())
}

///|
test "handle_local_command returns unchanged history for prompt command" {
  let cfg = sample_cfg()
  let history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
    @model.user_message("hello"),
  ]
  let next_history = handle_local_command(
    "/prompt",
    cfg,
    sample_tools(),
    history,
  ) catch {
    _ => None
  }
  @debug.assert_eq(next_history is Some(_), true)
  @debug.assert_eq(next_history.unwrap().length(), history.length())
}

///|
test "handle_local_command rejects invalid local tool json" {
  let cfg = sample_cfg()
  let history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
  ]
  let result = handle_local_command(
    "/call be-read not-json",
    cfg,
    sample_tools(),
    history,
  ) catch {
    err => {
      @debug.assert_eq(
        render_agent_error(err),
        "local tool call requires valid JSON arguments",
      )
      return
    }
  }
  ignore(result)
  @debug.assert_eq("error", "expected")
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
test "handle_local_command rejects unknown tool help target" {
  let cfg = sample_cfg()
  let history : Array[@model.Message] = [
    @model.system_message(cfg.agent.system_prompt),
  ]
  let result = handle_local_command(
    "/toolhelp nope",
    cfg,
    sample_tools(),
    history,
  ) catch {
    err => {
      @debug.assert_eq(render_agent_error(err), "unknown tool: nope")
      return
    }
  }
  ignore(result)
  @debug.assert_eq("error", "expected")
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
