///|
fn render_bool(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}

///|
fn render_string(value : String) -> String {
  let builder = StringBuilder::StringBuilder()
  builder.write_string("\"")
  for ch in value {
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
    } else {
      builder.write_string("\{ch}")
    }
  }
  builder.write_string("\"")
  builder.to_string()
}

///|
fn render_string_array(items : Array[String]) -> String {
  "[\{items.map(render_string).join(", ")}]"
}

///|
fn encode_config(cfg : AppConfig) -> String {
  let lines = [
    "[model]",
    "base_url = \{render_string(cfg.model.base_url)}",
    "model = \{render_string(cfg.model.model)}",
    "api_key = \{render_string(cfg.model.api_key)}",
    "temperature = \{cfg.model.temperature}",
    "max_tokens = \{cfg.model.max_tokens}",
    "",
    "[agent]",
    "system_prompt = \{render_string(cfg.agent.system_prompt)}",
    "max_turns = \{cfg.agent.max_turns}",
    "max_tool_calls_per_turn = \{cfg.agent.max_tool_calls_per_turn}",
    "workdir = \{render_string(cfg.agent.workdir)}",
    "",
    "[tools]",
    "better_edit_tools_cmd = \{render_string(cfg.tools.better_edit_tools_cmd)}",
    "better_edit_tools_args = \{render_string_array(cfg.tools.better_edit_tools_args)}",
    "startup_timeout_ms = \{cfg.tools.startup_timeout_ms}",
    "call_timeout_ms = \{cfg.tools.call_timeout_ms}",
    "",
    "[ui]",
    "show_timestamps = \{render_bool(cfg.ui.show_timestamps)}",
    "show_tool_calls = \{render_bool(cfg.ui.show_tool_calls)}",
    "show_raw_tool_results = \{render_bool(cfg.ui.show_raw_tool_results)}",
    "",
  ]
  lines.join("\n")
}

///|
pub fn save_config(path : String, cfg : AppConfig) -> Unit raise ConfigError {
  @native.write_file(path, encode_config(cfg)) catch {
    _ => raise ConfigError::Io(message="failed to write config file")
  }
}
