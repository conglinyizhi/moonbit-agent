///|
suberror NativeError {
  Failure(message~ : String)
}

///|
#borrow(path)
extern "c" fn native_read_file(path : Bytes) -> Bytes = "native_read_file"

///|
#borrow(path, content)
extern "c" fn native_write_file(path : Bytes, content : Bytes) -> Bytes = "native_write_file"

///|
#borrow(command, stdin_data)
extern "c" fn native_run_command(command : Bytes, stdin_data : Bytes) -> Bytes = "native_run_command"

///|
extern "c" fn native_read_stdin_line() -> Bytes = "native_read_stdin_line"

///|
pub fn read_file(path : String) -> String raise NativeError {
  let out = @utf8.decode_lossy(native_read_file(@utf8.encode(path)))
  if out.has_prefix("ERR:") {
    raise NativeError::Failure(message=out[4:].to_owned())
  }
  out
}

///|
pub fn write_file(path : String, content : String) -> Unit raise NativeError {
  let out = @utf8.decode_lossy(
    native_write_file(@utf8.encode(path), @utf8.encode(content)),
  )
  if out != "OK" {
    raise NativeError::Failure(message=out)
  }
}

///|
pub fn run_command(
  command : String,
  stdin_data? : String = "",
) -> String raise NativeError {
  let out = @utf8.decode_lossy(
    native_run_command(@utf8.encode(command), @utf8.encode(stdin_data)),
  )
  if out.has_prefix("ERR:") {
    raise NativeError::Failure(message=out[4:].to_owned())
  }
  out
}

///|
pub fn read_stdin_line() -> String? {
  let out = @utf8.decode_lossy(native_read_stdin_line())
  if out == "__EOF__" {
    None
  } else {
    Some(out)
  }
}
