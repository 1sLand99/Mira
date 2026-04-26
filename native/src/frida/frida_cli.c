#include "frida-core.h"
#include "mira/frida_cli_embed.h"

#include <errno.h>
#include <stdarg.h>

#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef enum { MIRA_FRIDA_MODE_BATCH, MIRA_FRIDA_MODE_REPL } MiraFridaMode;

typedef struct {
  MiraFridaMode mode;
  GMainLoop *loop;
  FridaDeviceManager *manager;
  FridaDevice *device;
  FridaSession *session;
  FridaScript *script;
  gboolean shutting_down;
  gboolean had_error;
  gboolean timed_out;
  gboolean interrupted;
  gint exit_code;
  guint pid;
  guint timeout_ms;
  guint timeout_source_id;
  guint input_source_id;
  GIOChannel *input_channel;
  gint input_fd;
  gboolean owns_input_fd;
  gboolean input_is_tty;
  gboolean awaiting_reply;
  gboolean quiet;
  guint next_request_id;
  guint pending_request_id;
  gchar *status_frida_version;
  gchar *status_arch;
  gchar *status_platform;
  gchar *prompt_target;
  gchar *startup_eval;
  gboolean status_java_available;
} MiraFridaRunContext;

static const gchar *kDefaultAddress = "127.0.0.1:27042";
static const guint kDefaultTimeoutMs = 3000;
static const gchar *kBatchPrelude =
    "(function () {\n"
    "  function miraDefer(fn) {\n"
    "    if (typeof setImmediate === 'function') {\n"
    "      setImmediate(fn);\n"
    "      return;\n"
    "    }\n"
    "    if (typeof setTimeout === 'function') {\n"
    "      setTimeout(fn, 0);\n"
    "      return;\n"
    "    }\n"
    "    fn();\n"
    "  }\n"
    "  if (typeof globalThis.Mira === 'undefined') {\n"
    "    globalThis.Mira = {\n"
    "      result: function (value) { send(value); },\n"
    "      done: function (code) { miraDefer(function () { send({ $fridaCli: { "
    "event: 'done', code: code === undefined ? 0 : code } }); }); },\n"
    "      exit: function (code) { miraDefer(function () { send({ $fridaCli: { "
    "event: 'done', code: code === undefined ? 0 : code } }); }); },\n"
    "      error: function (message) { miraDefer(function () { send({ "
    "$fridaCli: { event: 'done', code: 1, error: String(message) } }); }); },\n"
    "      fail: function (message) { miraDefer(function () { send({ "
    "$fridaCli: { event: 'done', code: 1, error: String(message) } }); }); },\n"
    "      status: function (payload) { send({ $fridaCli: { event: 'status', "
    "data: payload } }); }\n"
    "    };\n"
    "  }\n"
    "})();\n";
static const gchar *kReplBootstrap =
    "(function () {\n"
    "  function stringifyError(error) {\n"
    "    try {\n"
    "      if (error && error.stack) return String(error.stack);\n"
    "    } catch (_) {}\n"
    "    try {\n"
    "      return String(error);\n"
    "    } catch (_) {}\n"
    "    return '<error>';\n"
    "  }\n"
    "  function toText(value) {\n"
    "    if (value === undefined) return 'undefined';\n"
    "    if (value === null) return 'null';\n"
    "    if (typeof value === 'string') return value;\n"
    "    try {\n"
    "      return JSON.stringify(value);\n"
    "    } catch (_) {}\n"
    "    try {\n"
    "      return String(value);\n"
    "    } catch (_) {}\n"
    "    return Object.prototype.toString.call(value);\n"
    "  }\n"
    "  function sendControl(event, fields) {\n"
    "    var payload = { event: event };\n"
    "    if (fields) {\n"
    "      for (var key in fields) payload[key] = fields[key];\n"
    "    }\n"
    "    send({ $fridaCli: payload });\n"
    "  }\n"
    "  function evaluate(code) {\n"
    "    var evaluator = function () { return (0, eval)(code); };\n"
    "    if (typeof Java !== 'undefined' && Java.available) {\n"
    "      try {\n"
    "        if (typeof Java.performNow === 'function') return "
    "Java.performNow(evaluator);\n"
    "      } catch (_) {}\n"
    "    }\n"
    "    return evaluator();\n"
    "  }\n"
    "  function handle(id, code) {\n"
    "    try {\n"
    "      var result = evaluate(code);\n"
    "      if (result && typeof result.then === 'function') {\n"
    "        result.then(function (value) {\n"
    "          sendControl('result', { id: id, text: toText(value) });\n"
    "        }, function (error) {\n"
    "          sendControl('error', { id: id, message: stringifyError(error) "
    "});\n"
    "        });\n"
    "      } else {\n"
    "        sendControl('result', { id: id, text: toText(result) });\n"
    "      }\n"
    "    } catch (error) {\n"
    "      sendControl('error', { id: id, message: stringifyError(error) });\n"
    "    }\n"
    "  }\n"
    "  function loop() {\n"
    "    recv('mira:eval', function (message) {\n"
    "      var payload = message.payload || {};\n"
    "      handle(payload.id || 0, String(payload.code || ''));\n"
    "      loop();\n"
    "    });\n"
    "  }\n"
    "  sendControl('ready', {\n"
    "    frida_version: Frida.version,\n"
    "    pid: Process.id,\n"
    "    arch: Process.arch,\n"
    "    platform: Process.platform,\n"
    "    java_available: (typeof Java !== 'undefined' && Java.available)\n"
    "  });\n"
    "  loop();\n"
    "})();\n";
static const gchar *kStatusScript =
    "Mira.status({\n"
    "  frida_version: Frida.version,\n"
    "  pid: Process.id,\n"
    "  arch: Process.arch,\n"
    "  platform: Process.platform,\n"
    "  java_available: (typeof Java !== 'undefined' && Java.available)\n"
    "});\n"
    "Mira.done(0);\n";
static const gchar *kVersionScript = "send({\n"
                                     "  frida: Frida.version,\n"
                                     "  pid: Process.id,\n"
                                     "  arch: Process.arch,\n"
                                     "  platform: Process.platform\n"
                                     "});\n"
                                     "Mira.done(0);\n";

static GMainLoop *g_active_loop = NULL;
static MiraFridaRunContext *g_active_context = NULL;

static gint g_cli_input_fd = STDIN_FILENO;
static gint g_cli_output_fd = STDOUT_FILENO;
static gint g_cli_error_fd = STDERR_FILENO;

static gboolean mira_cli_fd_is_tty(gint fd);
static void mira_cli_write_formatted(gint fd, const gchar *format,
                                     va_list args);
static void mira_cli_print(const gchar *format, ...);
static void mira_cli_printerr(const gchar *format, ...);

void mira_frida_cli_set_stdio(int input_fd, int output_fd, int error_fd) {
  g_cli_input_fd = input_fd >= 0 ? input_fd : STDIN_FILENO;
  g_cli_output_fd = output_fd >= 0 ? output_fd : STDOUT_FILENO;
  g_cli_error_fd = error_fd >= 0 ? error_fd : STDERR_FILENO;
}

void mira_frida_cli_reset_stdio(void) {
  g_cli_input_fd = STDIN_FILENO;
  g_cli_output_fd = STDOUT_FILENO;
  g_cli_error_fd = STDERR_FILENO;
}

static gboolean mira_cli_fd_is_tty(gint fd) { return fd >= 0 && isatty(fd); }

static void mira_cli_write_formatted(gint fd, const gchar *format,
                                     va_list args) {
  gchar stack[1024];
  va_list copy;
  gint needed;
  ssize_t offset = 0;

  va_copy(copy, args);
  needed = vsnprintf(stack, sizeof(stack), format, copy);
  va_end(copy);

  if (needed < 0)
    return;

  if ((gsize)needed < sizeof(stack)) {
    while (offset < needed) {
      ssize_t written = write(fd, stack + offset, (size_t)(needed - offset));
      if (written < 0 && errno == EINTR)
        continue;
      if (written <= 0)
        break;
      offset += written;
    }
    return;
  }

  gchar *heap = g_malloc((gsize)needed + 1U);
  va_copy(copy, args);
  vsnprintf(heap, (gsize)needed + 1U, format, copy);
  va_end(copy);
  offset = 0;
  while (offset < needed) {
    ssize_t written = write(fd, heap + offset, (size_t)(needed - offset));
    if (written < 0 && errno == EINTR)
      continue;
    if (written <= 0)
      break;
    offset += written;
  }
  g_free(heap);
}

static void mira_cli_print(const gchar *format, ...) {
  va_list args;
  va_start(args, format);
  mira_cli_write_formatted(g_cli_output_fd, format, args);
  va_end(args);
}

static void mira_cli_printerr(const gchar *format, ...) {
  va_list args;
  va_start(args, format);
  mira_cli_write_formatted(g_cli_error_fd, format, args);
  va_end(args);
}

static void print_usage(const char *program_name);
static gboolean parse_common_option(int argc, char **argv, int *index,
                                    const char **address,
                                    gchar **owned_address);
static gboolean parse_timeout_option(int argc, char **argv, int *index,
                                     guint *timeout_ms);
static gboolean parse_load_option(int argc, char **argv, int *index,
                                  const char **path);
static gboolean parse_target_name_option(int argc, char **argv, int *index,
                                         const char **target_name);
static gboolean parse_target_pid_option(int argc, char **argv, int *index,
                                        guint *target_pid);
static gchar *join_arguments(int argc, char **argv, int start_index);
static gchar *wrap_batch_source(const gchar *source);
static gchar *wrap_repl_source(const gchar *source);
static gchar *wrap_eval_source(const gchar *code);
static gchar *load_script_source(const gchar *path, GError **error);
static FridaDevice *open_remote_device(const char *address,
                                       FridaDeviceManager **manager_out,
                                       GError **error);
static FridaProcessList *enumerate_processes(FridaDevice *device,
                                             GError **error);
static guint resolve_target_pid(FridaDevice *device, const gchar *target_name,
                                guint target_pid, gchar **resolved_name_out,
                                GError **error);
static gboolean connect_session(MiraFridaRunContext *context,
                                const char *address,
                                const gchar *target_name_override,
                                guint target_pid_override, GError **error);
static gboolean load_script(MiraFridaRunContext *context, const gchar *name,
                            const gchar *source, GError **error);
static int command_status(const char *address, guint timeout_ms);
static int command_batch(const char *address, const gchar *target_name,
                         guint target_pid, const gchar *source,
                         guint timeout_ms, const gchar *script_name);
static int command_repl(const char *address, const gchar *target_name,
                        guint target_pid, gboolean quiet,
                        const gchar *startup_eval);
static int command_repl_with_source(const char *address,
                                    const gchar *target_name,
                                    guint target_pid, const gchar *source,
                                    const gchar *script_name,
                                    gboolean reopen_tty, gboolean quiet,
                                    const gchar *startup_eval);
static int command_eval(const char *address, const gchar *target_name,
                        guint target_pid, const gchar *source,
                        guint timeout_ms);
static int command_version_compat(const char *address, const gchar *target_name,
                                  guint target_pid, guint timeout_ms);
static gboolean start_context_loop(MiraFridaRunContext *context,
                                   guint timeout_ms);
static void cleanup_context(MiraFridaRunContext *context);
static gboolean setup_repl_input(MiraFridaRunContext *context,
                                 gboolean reopen_tty);
static void print_repl_prompt(MiraFridaRunContext *context);
static gboolean post_repl_request(MiraFridaRunContext *context,
                                  const gchar *line);
static gboolean on_repl_input(GIOChannel *channel, GIOCondition condition,
                              gpointer user_data);
static void on_session_detached(FridaSession *session,
                                FridaSessionDetachReason reason,
                                FridaCrash *crash, gpointer user_data);
static void on_script_message(FridaScript *script, const gchar *message,
                              GBytes *data, gpointer user_data);
static gboolean handle_control_message(MiraFridaRunContext *context,
                                       JsonNode *payload);
static gboolean on_timeout(gpointer user_data);
static gboolean stop_loop(gpointer user_data);
static void on_signal(int signo);
static void remove_source_if_present(guint *source_id);
static const gchar *json_object_get_optional_string(JsonObject *object,
                                                    const gchar *name);
static gint json_object_get_optional_int(JsonObject *object, const gchar *name,
                                         gint fallback);
static gboolean json_object_get_optional_boolean(JsonObject *object,
                                                 const gchar *name,
                                                 gboolean fallback);
static void print_payload_stdout(JsonNode *payload);

int mira_frida_cli_main(int argc, char *argv[]) {
  const char *address = kDefaultAddress;
  gchar *owned_address = NULL;
  const char *load_path = NULL;
  const char *target_name = NULL;
  guint target_pid = 0;
  guint timeout_ms = kDefaultTimeoutMs;
  gboolean show_help = FALSE;
  gboolean show_status = FALSE;
  gboolean show_version_compat = FALSE;
  gboolean eval_compat = FALSE;
  gboolean force_batch = FALSE;
  gboolean force_repl = FALSE;
  gboolean quiet = FALSE;
  gchar *inline_source = NULL;
  gchar *eval_source = NULL;
  int i;
  int exit_code;

  frida_init();

  if (argc == 1) {
    if (mira_cli_fd_is_tty(g_cli_input_fd))
      return command_repl(address, NULL, 0, FALSE, NULL);
    inline_source = load_script_source("-", NULL);
    if (inline_source == NULL) {
      mira_cli_printerr("frida: failed to read script from stdin\n");
      return 2;
    }
    exit_code = command_repl_with_source(address, NULL, 0, inline_source,
                                         "stdin", TRUE, FALSE, NULL);
    g_free(inline_source);
    return exit_code;
  }

  for (i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
      show_help = TRUE;
      continue;
    }
    if (strcmp(argv[i], "--status") == 0) {
      show_status = TRUE;
      continue;
    }
    if (strcmp(argv[i], "--batch") == 0) {
      force_batch = TRUE;
      continue;
    }
    if (strcmp(argv[i], "--repl") == 0) {
      force_repl = TRUE;
      continue;
    }
    if (strcmp(argv[i], "-q") == 0) {
      quiet = TRUE;
      continue;
    }
    if (strcmp(argv[i], "-e") == 0 || strcmp(argv[i], "--eval") == 0) {
      gchar *joined;
      if (i + 1 >= argc) {
        mira_cli_printerr("%s requires a value\n", argv[i]);
        g_free(eval_source);
        g_free(owned_address);
        return 2;
      }
      joined = eval_source == NULL
                   ? g_strdup(argv[++i])
                   : g_strjoin("\n", eval_source, argv[++i], NULL);
      g_free(eval_source);
      eval_source = joined;
      continue;
    }
    if (parse_common_option(argc, argv, &i, &address, &owned_address))
      continue;
    if (parse_timeout_option(argc, argv, &i, &timeout_ms))
      continue;
    if (parse_load_option(argc, argv, &i, &load_path))
      continue;
    if (parse_target_name_option(argc, argv, &i, &target_name))
      continue;
    if (parse_target_pid_option(argc, argv, &i, &target_pid))
      continue;

    if (strcmp(argv[i], "probe") == 0) {
      show_status = TRUE;
      continue;
    }
    if (strcmp(argv[i], "version") == 0) {
      show_version_compat = TRUE;
      continue;
    }
    if (strcmp(argv[i], "eval") == 0) {
      eval_compat = TRUE;
      inline_source = join_arguments(argc, argv, i + 1);
      break;
    }

    mira_cli_printerr("frida: unsupported argument: %s\n", argv[i]);
    print_usage(argv[0]);
    g_free(eval_source);
    g_free(owned_address);
    return 2;
  }

  if (show_help) {
    print_usage(argv[0]);
    g_free(eval_source);
    g_free(owned_address);
    return 0;
  }

  if (show_status) {
    exit_code = command_status(address, timeout_ms);
    g_free(eval_source);
    g_free(owned_address);
    return exit_code;
  }

  if (show_version_compat) {
    exit_code =
        command_version_compat(address, target_name, target_pid, timeout_ms);
    g_free(eval_source);
    g_free(owned_address);
    return exit_code;
  }

  if (eval_compat) {
    if (inline_source == NULL || *inline_source == '\0') {
      mira_cli_printerr("frida eval: missing JavaScript source\n");
      g_free(inline_source);
      g_free(eval_source);
      g_free(owned_address);
      return 2;
    }
    exit_code = command_batch(address, target_name, target_pid, inline_source,
                              timeout_ms, "eval");
    g_free(inline_source);
    g_free(eval_source);
    g_free(owned_address);
    return exit_code;
  }

  if (force_repl && load_path == NULL && !force_batch && !show_status &&
      !show_version_compat && !eval_compat && eval_source == NULL) {
    exit_code = command_repl(address, target_name, target_pid, quiet, NULL);
    g_free(eval_source);
    g_free(owned_address);
    return exit_code;
  }

  if (load_path != NULL) {
    GError *error = NULL;
    gchar *source = load_script_source(load_path, &error);
    if (source == NULL) {
      mira_cli_printerr("frida: %s\n", error != NULL ? error->message
                                                     : "failed to load script");
      if (error != NULL)
        g_error_free(error);
      g_free(eval_source);
      g_free(owned_address);
      return 2;
    }
    if (quiet && eval_source != NULL) {
      gchar *combined = g_strjoin("\n", source, eval_source, NULL);
      exit_code =
          command_eval(address, target_name, target_pid, combined, timeout_ms);
      g_free(combined);
    } else if (force_batch) {
      exit_code = command_batch(address, target_name, target_pid, source,
                                timeout_ms, load_path);
    } else {
      exit_code = command_repl_with_source(
          address, target_name, target_pid, source, load_path,
          !mira_cli_fd_is_tty(g_cli_input_fd), quiet, eval_source);
    }
    g_free(source);
    g_free(eval_source);
    g_free(owned_address);
    return exit_code;
  }

  if (eval_source != NULL) {
    exit_code = quiet ? command_eval(address, target_name, target_pid,
                                     eval_source, timeout_ms)
                      : command_repl(address, target_name, target_pid, quiet,
                                     eval_source);
    g_free(eval_source);
    g_free(owned_address);
    return exit_code;
  }

  if (!mira_cli_fd_is_tty(g_cli_input_fd)) {
    GError *error = NULL;
    gchar *source = load_script_source("-", &error);
    if (source == NULL) {
      mira_cli_printerr("frida: %s\n", error != NULL ? error->message
                                                     : "failed to read stdin");
      if (error != NULL)
        g_error_free(error);
      g_free(owned_address);
      return 2;
    }
    exit_code = force_batch ? command_batch(address, target_name, target_pid,
                                            source, timeout_ms, "stdin")
                            : command_repl_with_source(
                                  address, target_name, target_pid, source,
                                  "stdin", TRUE, quiet, NULL);
    g_free(source);
    g_free(owned_address);
    return exit_code;
  }

  if (force_batch) {
    mira_cli_printerr(
        "frida: --batch requires -l FILE or stdin script input\n");
    g_free(owned_address);
    return 2;
  }

  exit_code = command_repl(address, target_name, target_pid, quiet, NULL);
  g_free(owned_address);
  return exit_code;
}

static void print_usage(const char *program_name) {
  gchar *basename = g_path_get_basename(program_name);
  const char *display_name =
      g_str_has_prefix(basename, "frida-native") ? "frida" : basename;
  mira_cli_print("Usage:\n"
                 "  %s --help\n"
                 "  %s [--address HOST:PORT|-H HOST] [-n NAME|-p PID] "
                 "[--timeout MS] --status\n"
                 "  %s [--address HOST:PORT|-H HOST] [-n NAME|-p PID] "
                 "[--timeout MS] [-l FILE] [-e CODE] [-q]\n"
                 "  cat script.js | %s [--address HOST:PORT|-H HOST] "
                 "[-n NAME|-p PID] [--timeout MS]\n"
                 "  %s [--address HOST:PORT|-H HOST] [-n NAME|-p PID] "
                 "[--timeout MS] [--batch] -l FILE\n"
                 "  %s [--address HOST:PORT|-H HOST] [-n NAME|-p PID]\n"
                 "\n"
                 "Interactive mode:\n"
                 "  frida                  open REPL against remote Gadget\n"
                 "  frida -l script.js     load script.js, then enter REPL\n"
                 "  frida -e CODE          evaluate CODE, then stay in REPL\n"
                 "\n"
                 "Batch mode:\n"
                 "  frida -q -e CODE       evaluate CODE and exit\n"
                 "  frida --batch -l FILE  run batch helper script and exit\n"
                 "\n"
                 "Batch helpers for MCP:\n"
                 "  Mira.done([code])  exit current batch script\n"
                 "  Mira.result(value) emit a result line\n"
                 "  Mira.error(message) emit an error and exit 1\n"
                 "\n"
                 "REPL helpers:\n"
                 "  .help             show REPL help\n"
                 "  .exit             exit REPL\n",
                 display_name, display_name, display_name, display_name,
                 display_name, display_name);
  g_free(basename);
}

static gboolean parse_common_option(int argc, char **argv, int *index,
                                    const char **address,
                                    gchar **owned_address) {
  if (strcmp(argv[*index], "--address") == 0 || strcmp(argv[*index], "-H") == 0 ||
      strcmp(argv[*index], "--host") == 0) {
    const gchar *value;
    if (*index + 1 >= argc) {
      mira_cli_printerr("%s requires a value\n", argv[*index]);
      return FALSE;
    }
    value = argv[++(*index)];
    if (strcmp(argv[*index - 1], "-H") == 0 ||
        strcmp(argv[*index - 1], "--host") == 0) {
      g_free(*owned_address);
      *owned_address = strchr(value, ':') != NULL
                           ? g_strdup(value)
                           : g_strdup_printf("%s:27042", value);
      *address = *owned_address;
    } else {
      *address = value;
    }
    return TRUE;
  }
  return FALSE;
}

static gboolean parse_target_name_option(int argc, char **argv, int *index,
                                         const char **target_name) {
  if (strcmp(argv[*index], "-n") == 0 ||
      strcmp(argv[*index], "--attach-name") == 0) {
    if (*index + 1 >= argc) {
      mira_cli_printerr("%s requires a value\n", argv[*index]);
      return FALSE;
    }
    *target_name = argv[++(*index)];
    return TRUE;
  }
  return FALSE;
}

static gboolean parse_target_pid_option(int argc, char **argv, int *index,
                                        guint *target_pid) {
  if (strcmp(argv[*index], "-p") == 0 ||
      strcmp(argv[*index], "--attach-pid") == 0) {
    gchar *end = NULL;
    unsigned long value;
    if (*index + 1 >= argc) {
      mira_cli_printerr("%s requires a value\n", argv[*index]);
      return FALSE;
    }
    value = strtoul(argv[++(*index)], &end, 10);
    if (end == NULL || *end != '\0' || value == 0) {
      mira_cli_printerr("invalid pid: %s\n", argv[*index]);
      return FALSE;
    }
    *target_pid = (guint)value;
    return TRUE;
  }
  return FALSE;
}

static gboolean parse_timeout_option(int argc, char **argv, int *index,
                                     guint *timeout_ms) {
  if (strcmp(argv[*index], "--timeout") == 0) {
    gchar *end = NULL;
    unsigned long value;
    if (*index + 1 >= argc) {
      mira_cli_printerr("--timeout requires a value\n");
      return FALSE;
    }
    value = strtoul(argv[++(*index)], &end, 10);
    if (end == NULL || *end != '\0' || value == 0) {
      mira_cli_printerr("invalid timeout: %s\n", argv[*index]);
      return FALSE;
    }
    *timeout_ms = (guint)value;
    return TRUE;
  }
  return FALSE;
}

static gboolean parse_load_option(int argc, char **argv, int *index,
                                  const char **path) {
  if (strcmp(argv[*index], "-l") == 0) {
    if (*index + 1 >= argc) {
      mira_cli_printerr("-l requires a script path or -\n");
      return FALSE;
    }
    *path = argv[++(*index)];
    return TRUE;
  }
  return FALSE;
}

static gchar *join_arguments(int argc, char **argv, int start_index) {
  GString *joined = g_string_new(NULL);
  int i;
  for (i = start_index; i < argc; i++) {
    if (i > start_index)
      g_string_append_c(joined, ' ');
    g_string_append(joined, argv[i]);
  }
  return g_string_free(joined, FALSE);
}

static gchar *wrap_batch_source(const gchar *source) {
  return g_strconcat(kBatchPrelude, source, "\n", NULL);
}

static gchar *wrap_repl_source(const gchar *source) {
  if (source == NULL || *source == '\0')
    return g_strdup(kReplBootstrap);
  return g_strconcat(source, "\n;\n", kReplBootstrap, NULL);
}

static gchar *wrap_eval_source(const gchar *code) {
  JsonBuilder *builder = json_builder_new();
  JsonGenerator *generator = json_generator_new();
  JsonNode *root = NULL;
  gchar *quoted = NULL;
  gchar *script = NULL;

  json_builder_begin_array(builder);
  json_builder_add_string_value(builder, code != NULL ? code : "");
  json_builder_end_array(builder);
  root = json_builder_get_root(builder);
  json_generator_set_root(generator, root);
  quoted = json_generator_to_data(generator, NULL);

  script = g_strdup_printf(
      "(function () {\n"
      "  function stringifyError(error) {\n"
      "    try { if (error && error.stack) return String(error.stack); } "
      "catch (_) {}\n"
      "    try { return String(error); } catch (_) {}\n"
      "    return '<error>';\n"
      "  }\n"
      "  function toText(value) {\n"
      "    if (value === undefined) return 'undefined';\n"
      "    if (value === null) return 'null';\n"
      "    if (typeof value === 'string') return value;\n"
      "    try { return JSON.stringify(value); } catch (_) {}\n"
      "    try { return String(value); } catch (_) {}\n"
      "    return Object.prototype.toString.call(value);\n"
      "  }\n"
      "  function evaluate(code) {\n"
      "    var evaluator = function () { return (0, eval)(code); };\n"
      "    if (typeof Java !== 'undefined' && Java.available) {\n"
      "      try {\n"
      "        if (typeof Java.performNow === 'function') return "
      "Java.performNow(evaluator);\n"
      "      } catch (_) {}\n"
      "    }\n"
      "    return evaluator();\n"
      "  }\n"
      "  var code = %s[0];\n"
      "  try {\n"
      "    var result = evaluate(code);\n"
      "    if (result && typeof result.then === 'function') {\n"
      "      result.then(function (value) {\n"
      "        send(toText(value));\n"
      "        Mira.done(0);\n"
      "      }, function (error) {\n"
      "        Mira.error(stringifyError(error));\n"
      "      });\n"
      "    } else {\n"
      "      send(toText(result));\n"
      "      Mira.done(0);\n"
      "    }\n"
      "  } catch (error) {\n"
      "    Mira.error(stringifyError(error));\n"
      "  }\n"
      "})();\n",
      quoted);

  if (root != NULL)
    json_node_free(root);
  g_object_unref(generator);
  g_object_unref(builder);
  g_free(quoted);
  return script;
}

static gchar *load_script_source(const gchar *path, GError **error) {
  gchar *contents = NULL;

  if (path != NULL && strcmp(path, "-") == 0) {
    GString *buffer = g_string_new(NULL);
    gchar chunk[4096];
    ssize_t n = 0;
    while ((n = read(g_cli_input_fd, chunk, sizeof(chunk))) > 0)
      g_string_append_len(buffer, chunk, (gssize)n);
    if (n < 0) {
      if (error != NULL)
        g_set_error(error, G_FILE_ERROR, G_FILE_ERROR_IO,
                    "failed to read script from stdin");
      g_string_free(buffer, TRUE);
      return NULL;
    }
    return g_string_free(buffer, FALSE);
  }

  if (!g_file_get_contents(path, &contents, NULL, error))
    return NULL;
  return contents;
}

static FridaDevice *open_remote_device(const char *address,
                                       FridaDeviceManager **manager_out,
                                       GError **error) {
  FridaDeviceManager *manager;
  FridaRemoteDeviceOptions *options;
  FridaDevice *device;

  manager = frida_device_manager_new();
  options = frida_remote_device_options_new();
  frida_remote_device_options_set_keepalive_interval(options, 0);

  device = frida_device_manager_add_remote_device_sync(manager, address,
                                                       options, NULL, error);
  g_object_unref(options);

  if (device == NULL) {
    frida_unref(manager);
    return NULL;
  }

  *manager_out = manager;
  return device;
}

static FridaProcessList *enumerate_processes(FridaDevice *device,
                                             GError **error) {
  return frida_device_enumerate_processes_sync(device, NULL, NULL, error);
}

static guint resolve_target_pid(FridaDevice *device, const gchar *target_name,
                                guint target_pid, gchar **resolved_name_out,
                                GError **error) {
  FridaProcessList *processes;
  gint count;
  guint pid = 0;
  gchar *resolved_name = NULL;
  gint i;

  processes = enumerate_processes(device, error);
  if (processes == NULL)
    return 0;

  count = frida_process_list_size(processes);
  for (i = 0; i < count; i++) {
    FridaProcess *process = frida_process_list_get(processes, i);
    guint process_pid = frida_process_get_pid(process);
    const gchar *process_name = frida_process_get_name(process);
    gboolean matches = FALSE;

    if (target_pid != 0)
      matches = process_pid == target_pid;
    else if (target_name != NULL)
      matches = g_strcmp0(process_name, target_name) == 0;
    else
      matches = i == 0;

    if (matches) {
      pid = process_pid;
      resolved_name = g_strdup(process_name);
      g_object_unref(process);
      break;
    }
    g_object_unref(process);
  }

  if (pid == 0 && count > 0 && (target_pid != 0 || target_name != NULL)) {
    if (target_pid != 0) {
      g_set_error(error, FRIDA_ERROR, FRIDA_ERROR_PROCESS_NOT_FOUND,
                  "remote Gadget process pid %u was not found", target_pid);
    } else {
      g_set_error(error, FRIDA_ERROR, FRIDA_ERROR_PROCESS_NOT_FOUND,
                  "remote Gadget process '%s' was not found", target_name);
    }
  } else if (pid == 0) {
    g_set_error(error, FRIDA_ERROR, FRIDA_ERROR_PROCESS_NOT_FOUND,
                "remote Gadget reported no processes");
  }

  if (resolved_name_out != NULL)
    *resolved_name_out = resolved_name;
  else
    g_free(resolved_name);

  frida_unref(processes);
  return pid;
}

static gboolean connect_session(MiraFridaRunContext *context,
                                const char *address,
                                const gchar *target_name_override,
                                guint target_pid_override, GError **error) {
  gchar *resolved_name = NULL;

  context->device = open_remote_device(address, &context->manager, error);
  if (context->device == NULL)
    return FALSE;

  context->pid = resolve_target_pid(context->device, target_name_override,
                                    target_pid_override, &resolved_name, error);
  if (context->pid == 0)
    return FALSE;

  g_free(context->prompt_target);
  if (resolved_name != NULL && *resolved_name != '\0')
    context->prompt_target = g_strdup_printf("Remote::%s ", resolved_name);
  else
    context->prompt_target = g_strdup_printf("Remote::PID::%u ", context->pid);
  g_free(resolved_name);

  context->session = frida_device_attach_sync(context->device, context->pid,
                                              NULL, NULL, error);
  if (context->session == NULL)
    return FALSE;

  g_signal_connect(context->session, "detached",
                   G_CALLBACK(on_session_detached), context);
  return TRUE;
}

static gboolean load_script(MiraFridaRunContext *context, const gchar *name,
                            const gchar *source, GError **error) {
  FridaScriptOptions *options;

  options = frida_script_options_new();
  frida_script_options_set_name(options, name);
  frida_script_options_set_runtime(options, FRIDA_SCRIPT_RUNTIME_DEFAULT);

  context->script = frida_session_create_script_sync(context->session, source,
                                                     options, NULL, error);
  g_object_unref(options);
  if (context->script == NULL)
    return FALSE;

  g_signal_connect(context->script, "message", G_CALLBACK(on_script_message),
                   context);
  frida_script_load_sync(context->script, NULL, error);
  return *error == NULL;
}

static int command_status(const char *address, guint timeout_ms) {
  FridaDeviceManager *manager = NULL;
  FridaDevice *device = NULL;
  FridaProcessList *processes = NULL;
  FridaSession *session = NULL;
  FridaScript *script = NULL;
  FridaScriptOptions *options = NULL;
  MiraFridaRunContext context;
  GError *error = NULL;
  gint count = 0;
  gint i;
  int exit_code = 0;
  gchar *wrapped_status = NULL;

  memset(&context, 0, sizeof(context));
  context.mode = MIRA_FRIDA_MODE_BATCH;
  context.exit_code = 0;
  context.timeout_ms = timeout_ms;

  device = open_remote_device(address, &manager, &error);
  if (device == NULL) {
    mira_cli_printerr("status failed: %s\n",
                      error != NULL ? error->message : "unknown error");
    exit_code = 3;
    goto cleanup;
  }

  mira_cli_print("address: %s\n", address);
  mira_cli_print("device: %s\n", frida_device_get_name(device));
  mira_cli_print("dtype: %d\n", frida_device_get_dtype(device));

  processes = enumerate_processes(device, &error);
  if (processes == NULL) {
    mira_cli_printerr("status failed: %s\n",
                      error != NULL ? error->message
                                    : "failed to enumerate processes");
    exit_code = 3;
    goto cleanup;
  }

  count = frida_process_list_size(processes);
  mira_cli_print("process_count: %d\n", count);
  for (i = 0; i < count; i++) {
    FridaProcess *process = frida_process_list_get(processes, i);
    mira_cli_print("  pid=%u name=%s\n", frida_process_get_pid(process),
                   frida_process_get_name(process));
    g_object_unref(process);
  }
  if (count == 0) {
    exit_code = 3;
    goto cleanup;
  }

  {
    FridaProcess *process = frida_process_list_get(processes, 0);
    context.pid = frida_process_get_pid(process);
    g_object_unref(process);
  }

  session = frida_device_attach_sync(device, context.pid, NULL, NULL, &error);
  if (session == NULL) {
    mira_cli_printerr("status failed: %s\n",
                      error != NULL ? error->message : "attach failed");
    exit_code = 3;
    goto cleanup;
  }
  context.session = session;
  g_signal_connect(session, "detached", G_CALLBACK(on_session_detached),
                   &context);

  wrapped_status = wrap_batch_source(kStatusScript);
  options = frida_script_options_new();
  frida_script_options_set_name(options, "mira-frida-status");
  frida_script_options_set_runtime(options, FRIDA_SCRIPT_RUNTIME_DEFAULT);
  script = frida_session_create_script_sync(session, wrapped_status, options,
                                            NULL, &error);
  if (script == NULL) {
    mira_cli_printerr("status failed: %s\n",
                      error != NULL ? error->message : "create script failed");
    exit_code = 4;
    goto cleanup;
  }
  context.script = script;
  g_signal_connect(script, "message", G_CALLBACK(on_script_message), &context);
  frida_script_load_sync(script, NULL, &error);
  if (error != NULL) {
    mira_cli_printerr("status failed: %s\n", error->message);
    exit_code = 4;
    goto cleanup;
  }

  if (!start_context_loop(&context, timeout_ms)) {
    if (context.interrupted)
      exit_code = 130;
    else if (context.timed_out)
      exit_code = 124;
    else if (context.exit_code != 0)
      exit_code = context.exit_code;
    else
      exit_code = 5;
    goto cleanup;
  }

  mira_cli_print("frida_version: %s\n", context.status_frida_version != NULL
                                            ? context.status_frida_version
                                            : "unknown");
  mira_cli_print("pid: %u\n", context.pid);
  mira_cli_print("arch: %s\n",
                 context.status_arch != NULL ? context.status_arch : "unknown");
  mira_cli_print("platform: %s\n", context.status_platform != NULL
                                       ? context.status_platform
                                       : "unknown");
  mira_cli_print("java_available: %s\n",
                 context.status_java_available ? "true" : "false");

cleanup:
  context.script = script;
  context.session = session;
  context.device = device;
  context.manager = manager;
  cleanup_context(&context);
  if (options != NULL)
    g_object_unref(options);
  if (processes != NULL)
    frida_unref(processes);
  if (error != NULL)
    g_error_free(error);
  g_free(wrapped_status);
  return exit_code;
}

static int command_batch(const char *address, const gchar *target_name,
                         guint target_pid, const gchar *source,
                         guint timeout_ms, const gchar *script_name) {
  MiraFridaRunContext context;
  GError *error = NULL;
  gchar *wrapped_source = NULL;
  int exit_code;

  memset(&context, 0, sizeof(context));
  context.mode = MIRA_FRIDA_MODE_BATCH;
  context.exit_code = 0;
  context.timeout_ms = timeout_ms;

  wrapped_source = wrap_batch_source(source);

  if (!connect_session(&context, address, target_name, target_pid, &error)) {
    mira_cli_printerr("frida: %s\n", error != NULL
                                         ? error->message
                                         : "failed to connect to Gadget");
    exit_code = 3;
    goto cleanup;
  }

  if (!load_script(&context,
                   script_name != NULL ? script_name : "mira-frida-batch",
                   wrapped_source, &error)) {
    mira_cli_printerr("frida: %s\n",
                      error != NULL ? error->message : "failed to load script");
    exit_code = 4;
    goto cleanup;
  }

  if (!start_context_loop(&context, timeout_ms)) {
    if (context.interrupted)
      exit_code = 130;
    else if (context.timed_out)
      exit_code = 124;
    else if (context.exit_code != 0)
      exit_code = context.exit_code;
    else
      exit_code = 5;
    goto cleanup;
  }

  exit_code = context.exit_code;

cleanup:
  if (error != NULL)
    g_error_free(error);
  g_free(wrapped_source);
  cleanup_context(&context);
  return exit_code;
}

static int command_repl(const char *address, const gchar *target_name,
                        guint target_pid, gboolean quiet,
                        const gchar *startup_eval) {
  return command_repl_with_source(address, target_name, target_pid, NULL, NULL,
                                  FALSE, quiet, startup_eval);
}

static int command_repl_with_source(const char *address,
                                    const gchar *target_name,
                                    guint target_pid, const gchar *source,
                                    const gchar *script_name,
                                    gboolean reopen_tty, gboolean quiet,
                                    const gchar *startup_eval) {
  MiraFridaRunContext context;
  GError *error = NULL;
  gchar *wrapped_source = NULL;
  int exit_code;

  memset(&context, 0, sizeof(context));
  context.mode = MIRA_FRIDA_MODE_REPL;
  context.exit_code = 0;
  context.next_request_id = 1;
  context.input_fd = -1;
  context.quiet = quiet;
  context.startup_eval =
      startup_eval != NULL ? g_strdup(startup_eval) : NULL;

  if (!connect_session(&context, address, target_name, target_pid, &error)) {
    mira_cli_printerr("frida: %s\n", error != NULL
                                         ? error->message
                                         : "failed to connect to Gadget");
    if (error != NULL)
      g_error_free(error);
    cleanup_context(&context);
    return 3;
  }

  wrapped_source = wrap_repl_source(source);
  if (!load_script(&context,
                   script_name != NULL ? script_name : "mira-frida-repl",
                   wrapped_source, &error)) {
    mira_cli_printerr("frida: %s\n",
                      error != NULL ? error->message : "failed to start REPL");
    if (error != NULL)
      g_error_free(error);
    g_free(wrapped_source);
    cleanup_context(&context);
    return 4;
  }

  setup_repl_input(&context, reopen_tty);

  if (!start_context_loop(&context, 0)) {
    if (context.interrupted)
      exit_code = 130;
    else if (context.exit_code != 0)
      exit_code = context.exit_code;
    else
      exit_code = 5;
  } else {
    exit_code = context.exit_code;
  }

  g_free(wrapped_source);
  cleanup_context(&context);
  return exit_code;
}

static int command_eval(const char *address, const gchar *target_name,
                        guint target_pid, const gchar *source,
                        guint timeout_ms) {
  gchar *wrapped = wrap_eval_source(source);
  int exit_code =
      command_batch(address, target_name, target_pid, wrapped, timeout_ms,
                    "mira-frida-eval");
  g_free(wrapped);
  return exit_code;
}

static int command_version_compat(const char *address, const gchar *target_name,
                                  guint target_pid, guint timeout_ms) {
  return command_batch(address, target_name, target_pid, kVersionScript,
                       timeout_ms, "version");
}

static gboolean start_context_loop(MiraFridaRunContext *context,
                                   guint timeout_ms) {
  signal(SIGINT, on_signal);
  signal(SIGTERM, on_signal);

  context->loop = g_main_loop_new(NULL, FALSE);
  g_active_loop = context->loop;
  g_active_context = context;

  if (timeout_ms > 0)
    context->timeout_source_id = g_timeout_add(timeout_ms, on_timeout, context);

  g_main_loop_run(context->loop);

  if (g_active_context == context)
    g_active_context = NULL;
  if (g_active_loop == context->loop)
    g_active_loop = NULL;

  remove_source_if_present(&context->timeout_source_id);

  return !context->had_error && !context->timed_out && !context->interrupted;
}

static void cleanup_context(MiraFridaRunContext *context) {
  context->shutting_down = TRUE;

  remove_source_if_present(&context->input_source_id);
  if (context->input_channel != NULL) {
    g_io_channel_unref(context->input_channel);
    context->input_channel = NULL;
  }
  if (context->owns_input_fd && context->input_fd >= 0) {
    close(context->input_fd);
    context->owns_input_fd = FALSE;
    context->input_fd = -1;
  }

  if (context->script != NULL) {
    g_signal_handlers_disconnect_by_func(
        context->script, G_CALLBACK(on_script_message), context);
    frida_script_unload_sync(context->script, NULL, NULL);
    frida_unref(context->script);
    context->script = NULL;
  }

  if (context->session != NULL) {
    g_signal_handlers_disconnect_by_func(
        context->session, G_CALLBACK(on_session_detached), context);
    frida_session_detach_sync(context->session, NULL, NULL);
    frida_unref(context->session);
    context->session = NULL;
  }

  if (context->device != NULL) {
    frida_unref(context->device);
    context->device = NULL;
  }

  if (context->manager != NULL) {
    frida_device_manager_close_sync(context->manager, NULL, NULL);
    frida_unref(context->manager);
    context->manager = NULL;
  }

  if (context->loop != NULL) {
    g_main_loop_unref(context->loop);
    context->loop = NULL;
  }

  g_free(context->status_frida_version);
  context->status_frida_version = NULL;
  g_free(context->status_arch);
  context->status_arch = NULL;
  g_free(context->status_platform);
  context->status_platform = NULL;
  g_free(context->prompt_target);
  context->prompt_target = NULL;
  g_free(context->startup_eval);
  context->startup_eval = NULL;
}

static void print_repl_prompt(MiraFridaRunContext *context) {
  if (context == NULL || context->quiet)
    return;
  mira_cli_print("[%s]-> ",
                 context->prompt_target != NULL ? context->prompt_target
                                                : "Remote::Gadget ");
}

static gboolean setup_repl_input(MiraFridaRunContext *context,
                                 gboolean reopen_tty) {
  gint input_fd = g_cli_input_fd;
  gboolean owns_input_fd = FALSE;

  if (reopen_tty && !mira_cli_fd_is_tty(g_cli_input_fd)) {
    input_fd =
        g_cli_input_fd >= 0 ? dup(g_cli_input_fd) : open("/dev/tty", O_RDONLY);
    owns_input_fd = input_fd >= 0;
  }

  context->input_fd = input_fd;
  context->owns_input_fd = owns_input_fd;
  context->input_is_tty = mira_cli_fd_is_tty(input_fd);

  if (input_fd < 0)
    return FALSE;

  context->input_channel = g_io_channel_unix_new(input_fd);
  g_io_channel_set_close_on_unref(context->input_channel, FALSE);
  context->input_source_id = g_io_add_watch(
      context->input_channel, G_IO_IN | G_IO_HUP | G_IO_ERR | G_IO_NVAL,
      on_repl_input, context);
  return TRUE;
}

static gboolean post_repl_request(MiraFridaRunContext *context,
                                  const gchar *line) {
  JsonBuilder *builder;
  JsonGenerator *generator;
  JsonNode *root;
  gchar *json;
  guint request_id;

  builder = json_builder_new();
  json_builder_begin_object(builder);
  json_builder_set_member_name(builder, "type");
  json_builder_add_string_value(builder, "mira:eval");
  json_builder_set_member_name(builder, "payload");
  json_builder_begin_object(builder);
  request_id = context->next_request_id++;
  json_builder_set_member_name(builder, "id");
  json_builder_add_int_value(builder, request_id);
  json_builder_set_member_name(builder, "code");
  json_builder_add_string_value(builder, line);
  json_builder_end_object(builder);
  json_builder_end_object(builder);

  generator = json_generator_new();
  root = json_builder_get_root(builder);
  json_generator_set_root(generator, root);
  json = json_generator_to_data(generator, NULL);

  frida_script_post(context->script, json, NULL);
  context->awaiting_reply = TRUE;
  context->pending_request_id = request_id;

  g_free(json);
  json_node_free(root);
  g_object_unref(generator);
  g_object_unref(builder);
  return TRUE;
}

static gboolean on_repl_input(GIOChannel *channel, GIOCondition condition,
                              gpointer user_data) {
  MiraFridaRunContext *context = user_data;
  gchar *line = NULL;
  gsize length = 0;
  GError *error = NULL;
  GIOStatus status;

  if ((condition & (G_IO_HUP | G_IO_ERR | G_IO_NVAL)) != 0) {
    context->interrupted = TRUE;
    context->input_source_id = 0;
    g_idle_add(stop_loop, context);
    return G_SOURCE_REMOVE;
  }

  status = g_io_channel_read_line(channel, &line, &length, NULL, &error);
  if (status == G_IO_STATUS_ERROR) {
    context->had_error = TRUE;
    context->exit_code = 5;
    mira_cli_printerr("frida repl read error: %s\n",
                      error != NULL ? error->message : "unknown error");
    if (error != NULL)
      g_error_free(error);
    g_free(line);
    context->input_source_id = 0;
    g_idle_add(stop_loop, context);
    return G_SOURCE_REMOVE;
  }

  if (status == G_IO_STATUS_EOF) {
    g_free(line);
    context->input_source_id = 0;
    g_idle_add(stop_loop, context);
    return G_SOURCE_REMOVE;
  }

  if (status == G_IO_STATUS_AGAIN) {
    g_free(line);
    return G_SOURCE_CONTINUE;
  }

  g_strchomp(line);
  if (*line == '\0') {
    if (!context->awaiting_reply)
      print_repl_prompt(context);
    g_free(line);
    return G_SOURCE_CONTINUE;
  }

  if (strcmp(line, ".exit") == 0 || strcmp(line, "exit") == 0) {
    g_free(line);
    context->input_source_id = 0;
    g_idle_add(stop_loop, context);
    return G_SOURCE_REMOVE;
  }

  if (strcmp(line, ".help") == 0 || strcmp(line, "help") == 0) {
    mira_cli_print(
        "REPL commands:\n  .help\n  .exit\n\nTip:\n  Type JavaScript directly. "
        "Example: Java.use('android.app.Activity')\n");
    print_repl_prompt(context);
    g_free(line);
    return G_SOURCE_CONTINUE;
  }

  if (context->awaiting_reply) {
    mira_cli_printerr("frida: previous evaluation is still running\n");
    print_repl_prompt(context);
    g_free(line);
    return G_SOURCE_CONTINUE;
  }

  post_repl_request(context, line);
  g_free(line);
  return G_SOURCE_CONTINUE;
}

static void on_session_detached(FridaSession *session,
                                FridaSessionDetachReason reason,
                                FridaCrash *crash, gpointer user_data) {
  MiraFridaRunContext *context = user_data;
  gchar *reason_str;

  if (context != NULL && context->shutting_down)
    return;

  reason_str = g_enum_to_string(FRIDA_TYPE_SESSION_DETACH_REASON, reason);
  mira_cli_printerr("session detached: reason=%s crash=%p\n", reason_str,
                    crash);
  g_free(reason_str);

  if (context != NULL) {
    context->had_error = TRUE;
    context->exit_code = 5;
  }
  g_idle_add(stop_loop, context);
}

static void on_script_message(FridaScript *script, const gchar *message,
                              GBytes *data, gpointer user_data) {
  MiraFridaRunContext *context = user_data;
  JsonParser *parser;
  JsonObject *root;
  const gchar *type;

  parser = json_parser_new();
  if (!json_parser_load_from_data(parser, message, -1, NULL)) {
    mira_cli_printerr("%s\n", message);
    g_object_unref(parser);
    return;
  }

  root = json_node_get_object(json_parser_get_root(parser));
  type = json_object_get_string_member(root, "type");

  if (strcmp(type, "log") == 0) {
    mira_cli_printerr("%s\n", json_object_get_string_member(root, "payload"));
  } else if (strcmp(type, "send") == 0 &&
             json_object_has_member(root, "payload")) {
    JsonNode *payload = json_object_get_member(root, "payload");
    if (!handle_control_message(context, payload)) {
      print_payload_stdout(payload);
      if (context->mode == MIRA_FRIDA_MODE_REPL && !context->awaiting_reply)
        print_repl_prompt(context);
    }
  } else if (strcmp(type, "error") == 0) {
    context->had_error = TRUE;
    if (context->exit_code == 0)
      context->exit_code = 5;
    mira_cli_printerr("%s\n", message);
    g_idle_add(stop_loop, context);
  } else {
    mira_cli_printerr("%s\n", message);
  }

  g_object_unref(parser);
}

static gboolean handle_control_message(MiraFridaRunContext *context,
                                       JsonNode *payload) {
  JsonObject *payload_object;
  JsonNode *control_node;
  JsonObject *control_object;
  const gchar *event;

  if (!JSON_NODE_HOLDS_OBJECT(payload))
    return FALSE;

  payload_object = json_node_get_object(payload);
  if (!json_object_has_member(payload_object, "$fridaCli"))
    return FALSE;

  control_node = json_object_get_member(payload_object, "$fridaCli");
  if (!JSON_NODE_HOLDS_OBJECT(control_node))
    return TRUE;

  control_object = json_node_get_object(control_node);
  event = json_object_get_optional_string(control_object, "event");
  if (event == NULL)
    return TRUE;

  if (strcmp(event, "done") == 0) {
    const gchar *error_message =
        json_object_get_optional_string(control_object, "error");
    context->exit_code =
        json_object_get_optional_int(control_object, "code", 0);
    if (error_message != NULL && *error_message != '\0')
      mira_cli_printerr("%s\n", error_message);
    if (context->exit_code != 0)
      context->had_error = TRUE;
    g_idle_add(stop_loop, context);
    return TRUE;
  }

  if (strcmp(event, "status") == 0 &&
      json_object_has_member(control_object, "data")) {
    JsonNode *data_node = json_object_get_member(control_object, "data");
    if (JSON_NODE_HOLDS_OBJECT(data_node)) {
      JsonObject *data_object = json_node_get_object(data_node);
      g_free(context->status_frida_version);
      context->status_frida_version = g_strdup(
          json_object_get_optional_string(data_object, "frida_version"));
      g_free(context->status_arch);
      context->status_arch =
          g_strdup(json_object_get_optional_string(data_object, "arch"));
      g_free(context->status_platform);
      context->status_platform =
          g_strdup(json_object_get_optional_string(data_object, "platform"));
      context->status_java_available = json_object_get_optional_boolean(
          data_object, "java_available", FALSE);
      context->pid = (guint)json_object_get_optional_int(data_object, "pid",
                                                         (gint)context->pid);
    }
    return TRUE;
  }

  if (strcmp(event, "ready") == 0) {
    const gchar *frida_version =
        json_object_get_optional_string(control_object, "frida_version");
    const gchar *arch = json_object_get_optional_string(control_object, "arch");
    const gchar *platform =
        json_object_get_optional_string(control_object, "platform");
    gboolean java_available = json_object_get_optional_boolean(
        control_object, "java_available", FALSE);
    gint pid =
        json_object_get_optional_int(control_object, "pid", (gint)context->pid);
    g_free(context->status_frida_version);
    context->status_frida_version =
        g_strdup(frida_version != NULL ? frida_version : "unknown");
    g_free(context->status_arch);
    context->status_arch = g_strdup(arch != NULL ? arch : "unknown");
    g_free(context->status_platform);
    context->status_platform =
        g_strdup(platform != NULL ? platform : "unknown");
    context->status_java_available = java_available;
    context->pid = (guint)pid;

    if (context->startup_eval != NULL && *context->startup_eval != '\0') {
      gchar *startup_eval = g_strdup(context->startup_eval);
      g_free(context->startup_eval);
      context->startup_eval = NULL;
      post_repl_request(context, startup_eval);
      g_free(startup_eval);
    } else {
      print_repl_prompt(context);
    }
    return TRUE;
  }

  if (strcmp(event, "result") == 0) {
    guint id = (guint)json_object_get_optional_int(control_object, "id", -1);
    const gchar *text = json_object_get_optional_string(control_object, "text");
    if (context->mode == MIRA_FRIDA_MODE_REPL && context->awaiting_reply &&
        id == context->pending_request_id) {
      mira_cli_print("%s\n", text != NULL ? text : "undefined");
      context->awaiting_reply = FALSE;
      context->pending_request_id = 0;
      print_repl_prompt(context);
    }
    return TRUE;
  }

  if (strcmp(event, "error") == 0) {
    guint id = (guint)json_object_get_optional_int(control_object, "id", -1);
    const gchar *message =
        json_object_get_optional_string(control_object, "message");
    if (context->mode == MIRA_FRIDA_MODE_REPL && context->awaiting_reply &&
        id == context->pending_request_id) {
      mira_cli_printerr("%s\n", message != NULL ? message : "unknown error");
      context->awaiting_reply = FALSE;
      context->pending_request_id = 0;
      print_repl_prompt(context);
    } else if (message != NULL) {
      mira_cli_printerr("%s\n", message);
    }
    return TRUE;
  }

  return TRUE;
}

static gboolean on_timeout(gpointer user_data) {
  MiraFridaRunContext *context = user_data;
  context->timed_out = TRUE;
  context->had_error = TRUE;
  context->exit_code = 124;
  mira_cli_printerr("frida: timed out after %u ms\n", context->timeout_ms);
  return stop_loop(user_data);
}

static gboolean stop_loop(gpointer user_data) {
  MiraFridaRunContext *context = user_data;
  GMainLoop *loop = context != NULL ? context->loop : g_active_loop;
  if (loop != NULL && g_main_loop_is_running(loop))
    g_main_loop_quit(loop);
  return G_SOURCE_REMOVE;
}

static void on_signal(int signo) {
  if (g_active_context != NULL) {
    g_active_context->interrupted = TRUE;
    if (g_active_context->exit_code == 0)
      g_active_context->exit_code = 130;
  }
  if (g_active_loop != NULL)
    g_idle_add(stop_loop, g_active_context);
}

static void remove_source_if_present(guint *source_id) {
  GMainContext *main_context;

  if (source_id == NULL || *source_id == 0)
    return;

  main_context = g_main_context_default();
  if (g_main_context_find_source_by_id(main_context, *source_id) != NULL)
    g_source_remove(*source_id);
  *source_id = 0;
}

static const gchar *json_object_get_optional_string(JsonObject *object,
                                                    const gchar *name) {
  if (object == NULL || !json_object_has_member(object, name))
    return NULL;
  return json_object_get_string_member(object, name);
}

static gint json_object_get_optional_int(JsonObject *object, const gchar *name,
                                         gint fallback) {
  if (object == NULL || !json_object_has_member(object, name))
    return fallback;
  return (gint)json_object_get_int_member(object, name);
}

static gboolean json_object_get_optional_boolean(JsonObject *object,
                                                 const gchar *name,
                                                 gboolean fallback) {
  if (object == NULL || !json_object_has_member(object, name))
    return fallback;
  return json_object_get_boolean_member(object, name);
}

static void print_payload_stdout(JsonNode *payload) {
  if (JSON_NODE_HOLDS_VALUE(payload) &&
      json_node_get_value_type(payload) == G_TYPE_STRING) {
    mira_cli_print("%s\n", json_node_get_string(payload));
  } else {
    gchar *payload_str = json_to_string(payload, FALSE);
    mira_cli_print("%s\n", payload_str);
    g_free(payload_str);
  }
}

#ifndef MIRA_FRIDA_CLI_EMBEDDED
int main(int argc, char *argv[]) { return mira_frida_cli_main(argc, argv); }
#endif
