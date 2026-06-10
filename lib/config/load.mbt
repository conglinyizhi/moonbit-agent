///|
fn strip_comment(line : String) -> String {
  let idx = line.find("#")
  match idx {
    Some(i) => line[:i].to_owned()
    None => line
  }
}

///|
fn parse_bool(raw : String) -> Bool raise ConfigError {
  let v = raw.trim().to_owned()
  if v == "true" {
    true
  } else if v == "false" {
    false
  } else {
    raise ConfigError::Parse(message="invalid bool: \{raw}")
  }
}

///|
fn parse_string(raw : String) -> String raise ConfigError {
  let v = raw.trim().to_owned()
  if v.length() >= 2 && v.has_prefix("\"") && v.has_suffix("\"") {
    v[1:v.length() - 1].to_owned()
  } else {
    raise ConfigError::Parse(message="expected quoted string: \{raw}")
  }
}

///|
fn parse_string_array(raw : String) -> Array[String] raise ConfigError {
  let v = raw.trim().to_owned()
  if !(v.has_prefix("[") && v.has_suffix("]")) {
    raise ConfigError::Parse(message="expected string array: \{raw}")
  }
  let body = v[1:v.length() - 1].trim().to_owned()
  if body == "" {
    []
  } else {
    let out : Array[String] = []
    for part in body.split(",") {
      out.push(parse_string(part.to_owned()))
    }
    out
  }
}

///|
fn parse_kv(line : String) -> (String, String)? {
  match line.split_once("=") {
    Some((left, right)) =>
      Some((left.trim().to_owned(), right.trim().to_owned()))
    None => None
  }
}

///|
fn require_api_key(cfg : AppConfig) -> Unit raise ConfigError {
  if cfg.model.api_key == "" {
    raise ConfigError::Missing(
      message="missing API key; set model.api_key_env target environment variable or model.api_key in agent.toml",
    )
  }
}

///|
pub fn load_config(path : String) -> AppConfig raise ConfigError {
  let content = @native.read_file(path) catch {
    _ => raise ConfigError::Io(message="failed to read config file")
  }
  let cfg = default_config()
  let mut section = ""
  let mut api_key_env = "OPENAI_API_KEY"
  for raw_line in content.split("\n") {
    let line = strip_comment(raw_line.to_owned()).trim().to_owned()
    if line == "" {
      continue
    }
    if line.has_prefix("[") && line.has_suffix("]") {
      section = line[1:line.length() - 1].to_owned()
      continue
    }
    match parse_kv(line) {
      Some((key, value)) =>
        match section {
          "model" =>
            match key {
              "base_url" => cfg.model.base_url = parse_string(value)
              "model" => cfg.model.model = parse_string(value)
              "api_key" => cfg.model.api_key = parse_string(value)
              "api_key_env" => api_key_env = parse_string(value)
              "temperature" =>
                cfg.model.temperature = @strconv.from_str(value) catch {
                  _ =>
                    raise ConfigError::Parse(
                      message="invalid temperature: \{value}",
                    )
                }
              "max_tokens" =>
                cfg.model.max_tokens = @strconv.from_str(value) catch {
                  _ =>
                    raise ConfigError::Parse(
                      message="invalid max_tokens: \{value}",
                    )
                }
              _ => ()
            }
          "agent" =>
            match key {
              "system_prompt" => cfg.agent.system_prompt = parse_string(value)
              "max_turns" =>
                cfg.agent.max_turns = @strconv.from_str(value) catch {
                  _ =>
                    raise ConfigError::Parse(
                      message="invalid max_turns: \{value}",
                    )
                }
              "max_tool_calls_per_turn" =>
                cfg.agent.max_tool_calls_per_turn = @strconv.from_str(value) catch {
                  _ =>
                    raise ConfigError::Parse(
                      message="invalid max_tool_calls_per_turn: \{value}",
                    )
                }
              "workdir" => cfg.agent.workdir = parse_string(value)
              _ => ()
            }
          "tools" =>
            match key {
              "better_edit_tools_cmd" =>
                cfg.tools.better_edit_tools_cmd = parse_string(value)
              "better_edit_tools_args" =>
                cfg.tools.better_edit_tools_args = parse_string_array(value)
              "startup_timeout_ms" =>
                cfg.tools.startup_timeout_ms = @strconv.from_str(value) catch {
                  _ =>
                    raise ConfigError::Parse(
                      message="invalid startup_timeout_ms: \{value}",
                    )
                }
              "call_timeout_ms" =>
                cfg.tools.call_timeout_ms = @strconv.from_str(value) catch {
                  _ =>
                    raise ConfigError::Parse(
                      message="invalid call_timeout_ms: \{value}",
                    )
                }
              _ => ()
            }
          "ui" =>
            match key {
              "show_timestamps" => cfg.ui.show_timestamps = parse_bool(value)
              "show_tool_calls" => cfg.ui.show_tool_calls = parse_bool(value)
              "show_raw_tool_results" =>
                cfg.ui.show_raw_tool_results = parse_bool(value)
              _ => ()
            }
          _ => ()
        }
      None => raise ConfigError::Parse(message="invalid line: \{line}")
    }
  }
  match @env.get_env_var(api_key_env) {
    Some(v) => cfg.model.api_key = v
    None => ()
  }
  require_api_key(cfg)
  cfg
}
