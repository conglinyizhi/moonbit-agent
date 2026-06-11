#include <moonbit.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static moonbit_bytes_t make_bytes_from_cstr(const char *src) {
  int32_t len = (int32_t)strlen(src);
  moonbit_bytes_t bytes = moonbit_make_bytes(len, 0);
  memcpy(bytes, src, len);
  return bytes;
}

static char *bytes_to_cstr(moonbit_bytes_t bytes) {
  int32_t len = Moonbit_array_length(bytes);
  char *buf = (char *)malloc((size_t)len + 1);
  memcpy(buf, bytes, (size_t)len);
  buf[len] = '\0';
  return buf;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t native_read_file(moonbit_bytes_t path_bytes) {
  char *path = bytes_to_cstr(path_bytes);
  struct stat st;
  if (stat(path, &st) != 0) {
    free(path);
    return make_bytes_from_cstr("ERR:failed to stat file");
  }
  if (!S_ISREG(st.st_mode)) {
    free(path);
    return make_bytes_from_cstr("ERR:path is not a regular file");
  }
  FILE *fp = fopen(path, "rb");
  free(path);
  if (!fp) {
    return make_bytes_from_cstr("ERR:failed to open file");
  }
  fseek(fp, 0, SEEK_END);
  long size = ftell(fp);
  rewind(fp);
  if (size < 0) {
    fclose(fp);
    return make_bytes_from_cstr("ERR:failed to stat file");
  }
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)size, 0);
  if (size > 0) {
    fread(out, 1, (size_t)size, fp);
  }
  fclose(fp);
  return out;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t native_write_file(moonbit_bytes_t path_bytes, moonbit_bytes_t content_bytes) {
  char *path = bytes_to_cstr(path_bytes);
  FILE *fp = fopen(path, "wb");
  free(path);
  if (!fp) {
    return make_bytes_from_cstr("ERR:failed to open file for write");
  }
  int32_t len = Moonbit_array_length(content_bytes);
  if (len > 0) {
    fwrite(content_bytes, 1, (size_t)len, fp);
  }
  fclose(fp);
  return make_bytes_from_cstr("OK");
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t native_run_command(moonbit_bytes_t command_bytes, moonbit_bytes_t stdin_bytes) {
  char *command = bytes_to_cstr(command_bytes);
  int32_t stdin_len = Moonbit_array_length(stdin_bytes);
  char stdin_path[] = "/tmp/moonbit-cmd-stdin-XXXXXX";
  int stdin_fd = -1;
  if (stdin_len > 0) {
    stdin_fd = mkstemp(stdin_path);
    if (stdin_fd < 0) {
      free(command);
      return make_bytes_from_cstr("ERR:failed to create stdin temp file");
    }
    if (write(stdin_fd, stdin_bytes, (size_t)stdin_len) != stdin_len) {
      close(stdin_fd);
      unlink(stdin_path);
      free(command);
      return make_bytes_from_cstr("ERR:failed to write stdin temp file");
    }
    close(stdin_fd);
  }
  size_t shell_len = strlen(command) + 128;
  if (stdin_len > 0) {
    shell_len += strlen(stdin_path);
  }
  char *shell_cmd = (char *)malloc(shell_len);
  if (stdin_len > 0) {
    snprintf(shell_cmd, shell_len, "(%s) < '%s' 2>&1", command, stdin_path);
  } else {
    snprintf(shell_cmd, shell_len, "(%s) 2>&1", command);
  }
  FILE *pipe = popen(shell_cmd, "r");
  free(command);
  free(shell_cmd);
  if (!pipe) {
    if (stdin_len > 0) {
      unlink(stdin_path);
    }
    return make_bytes_from_cstr("ERR:failed to start command");
  }
  char *buf = NULL;
  size_t cap = 0;
  size_t len = 0;
  char chunk[4096];
  while (!feof(pipe)) {
    size_t n = fread(chunk, 1, sizeof(chunk), pipe);
    if (n == 0) {
      break;
    }
    if (len + n + 1 > cap) {
      cap = (len + n + 1) * 2;
      buf = (char *)realloc(buf, cap);
    }
    memcpy(buf + len, chunk, n);
    len += n;
  }
  int status = pclose(pipe);
  if (stdin_len > 0) {
    unlink(stdin_path);
  }
  if (!buf) {
    buf = (char *)malloc(1);
    buf[0] = '\0';
  } else {
    buf[len] = '\0';
  }
  if (status != 0) {
    size_t msg_len = len + 32;
    char *msg = (char *)malloc(msg_len);
    snprintf(msg, msg_len, "ERR:%s", buf);
    moonbit_bytes_t out = make_bytes_from_cstr(msg);
    free(buf);
    free(msg);
    return out;
  }
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)len, 0);
  if (len > 0) {
    memcpy(out, buf, len);
  }
  free(buf);
  return out;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t native_read_stdin_line(void) {
  char *line = NULL;
  size_t cap = 0;
  ssize_t n = getline(&line, &cap, stdin);
  if (n < 0) {
    free(line);
    return make_bytes_from_cstr("__EOF__");
  }
  while (n > 0 && (line[n - 1] == '\n' || line[n - 1] == '\r')) {
    line[--n] = '\0';
  }
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)n, 0);
  if (n > 0) {
    memcpy(out, line, (size_t)n);
  }
  free(line);
  return out;
}
