///|
pub suberror HttpError {
  Failure(message~ : String)
}

///|
fn shell_quote(input : String) -> String {
  "'\{input.replace(old="'", new="'\"'\"'")}'"
}

///|
pub fn post_json(
  url : String,
  api_key : String,
  body : String,
) -> String raise HttpError {
  let auth_header = "Authorization: Bearer \{api_key}"
  let cmd = "curl -sS \{shell_quote(url)} -H 'Content-Type: application/json' -H \{shell_quote(auth_header)} -d \{shell_quote(body)}"
  @native.run_command(cmd) catch {
    _ => raise HttpError::Failure(message="failed to execute curl")
  }
}
