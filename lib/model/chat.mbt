///|
pub struct ToolDef {
  name : String
  description : String
  input_schema : Json
}

///|
pub fn ToolDef::make(
  name : String,
  description : String,
  input_schema : Json,
) -> ToolDef {
  { name, description, input_schema }
}

///|
pub struct ToolCall {
  id : String
  name : String
  arguments_json : String
}

///|
pub fn ToolCall::make(
  id : String,
  name : String,
  arguments_json : String,
) -> ToolCall {
  { id, name, arguments_json }
}

///|
pub struct ToolResult {
  tool_call_id : String
  content_text : String
  is_error : Bool
}

///|
pub fn ToolResult::make(
  tool_call_id : String,
  content_text : String,
  is_error : Bool,
) -> ToolResult {
  { tool_call_id, content_text, is_error }
}

///|
pub enum Message {
  System(String)
  User(String)
  Assistant(String)
  Tool(call_id~ : String, name~ : String, content~ : String, is_error~ : Bool)
}

///|
pub struct ModelReply {
  content : String
  tool_calls : Array[ToolCall]
}

///|
pub fn ModelReply::make(
  content : String,
  tool_calls : Array[ToolCall],
) -> ModelReply {
  { content, tool_calls }
}

///|
pub fn system_message(content : String) -> Message {
  System(content)
}

///|
pub fn user_message(content : String) -> Message {
  User(content)
}

///|
pub fn assistant_message(content : String) -> Message {
  Assistant(content)
}

///|
pub fn tool_message(
  call_id : String,
  name : String,
  content : String,
  is_error : Bool,
) -> Message {
  Tool(call_id~, name~, content~, is_error~)
}

///|
pub fn message_to_json(message : Message) -> Json {
  match message {
    System(content) => { "role": "system", "content": content }
    User(content) => { "role": "user", "content": content }
    Assistant(content) => { "role": "assistant", "content": content }
    Tool(call_id~, name~, content~, is_error~) =>
      {
        "role": "tool",
        "tool_call_id": call_id,
        "name": name,
        "content": content,
        "is_error": is_error,
      }
  }
}

///|
pub fn tool_defs_to_json(tools : Array[ToolDef]) -> Json {
  Json::array(
    tools.map(tool => {
      "type": "function",
      "function": {
        "name": tool.name,
        "description": tool.description,
        "parameters": tool.input_schema,
      },
    }),
  )
}
