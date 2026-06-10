///|
pub struct ModelConfig {
  mut base_url : String
  mut model : String
  mut api_key : String
  mut temperature : Double
  mut max_tokens : Int
}

///|
pub struct AgentConfig {
  mut system_prompt : String
  mut max_turns : Int
  mut max_tool_calls_per_turn : Int
  mut workdir : String
}

///|
pub struct ToolsConfig {
  mut better_edit_tools_cmd : String
  mut better_edit_tools_args : Array[String]
  mut startup_timeout_ms : Int
  mut call_timeout_ms : Int
}

///|
pub struct UiConfig {
  mut show_timestamps : Bool
  mut show_tool_calls : Bool
  mut show_raw_tool_results : Bool
}

///|
pub struct AppConfig {
  model : ModelConfig
  agent : AgentConfig
  tools : ToolsConfig
  ui : UiConfig
}

///|
pub fn default_config() -> AppConfig {
  {
    model: {
      base_url: "https://api.openai.com/v1",
      model: "gpt-4o-mini",
      api_key: "",
      temperature: 0.2,
      max_tokens: 2048,
    },
    agent: {
      system_prompt: "You are a pragmatic coding agent. Use tools when needed and keep answers concise.",
      max_turns: 8,
      max_tool_calls_per_turn: 6,
      workdir: @env.current_dir().unwrap_or("./"),
    },
    tools: {
      better_edit_tools_cmd: "./_build/native/debug/build/cmd/better-edit-tools/better-edit-tools.exe",
      better_edit_tools_args: [],
      startup_timeout_ms: 3000,
      call_timeout_ms: 20000,
    },
    ui: {
      show_timestamps: false,
      show_tool_calls: true,
      show_raw_tool_results: false,
    },
  }
}

///|
pub suberror ConfigError {
  Io(message~ : String)
  Parse(message~ : String)
  Missing(message~ : String)
}
