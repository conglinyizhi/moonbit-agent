///|
test "run_command handles shell commands containing single quotes" {
  let output = run_command("printf 'hello'")
  @debug.assert_eq(output, "hello")
}

///|
test "run_command forwards stdin data to command" {
  let output = run_command("cat", stdin_data="alpha\nbeta\n")
  @debug.assert_eq(output, "alpha\nbeta\n")
}

///|
test "read_file rejects directory paths" {
  let _ = read_file(".") catch {
    Failure(message~) => {
      @debug.assert_eq(message, "path is not a regular file")
      return
    }
  }
  @debug.assert_eq("error", "expected")
}
