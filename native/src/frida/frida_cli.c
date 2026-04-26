#include "frida-core.h"

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef enum {
  MIRA_FRIDA_MODE_BATCH,
  MIRA_FRIDA_MODE_REPL
} MiraFridaMode;

typedef struct {
  MiraFridaMode mode;
  GMainLoop * loop;
  FridaDeviceManager * manager;
  FridaDevice * device;
  FridaSession * session;
  FridaScript * script;
  gboolean shutting_down;
  gboolean had_error;
  gboolean timed_out;
  gboolean interrupted;
  gint exit_code;
  guint pid;
  guint timeout_ms;
  guint timeout_source_id;
  guint stdin_source_id;
  GIOChannel * stdin_channel;
  gboolean awaiting_reply;
  guint next_request_id;
  guint pending_request_id;
  gchar * status_frida_version;
  gchar * status_arch;
  gchar * status_platform;
  gboolean status_java_available;
} MiraFridaRunContext;

static const gchar * kDefaultAddress = "127.0.0.1:27042";
static const guint kDefaultTimeoutMs = 3000;
static const gchar * kBatchPrelude =
    "(function () {\n"
    "  if (typeof globalThis.Mira === 'undefined') {\n"
    "    globalThis.Mira = {\n"
    "      result: function (value) { send(value); },\n"
    "      done: function (code) { send({ $fridaCli: { event: 'done', code: code === undefined ? 0 : code } }); },\n"
    "      exit: function (code) { send({ $fridaCli: { event: 'done', code: code === undefined ? 0 : code } }); },\n"
    "      error: function (message) { send({ $fridaCli: { event: 'done', code: 1, error: String(message) } }); },\n"
    "      fail: function (message) { send({ $fridaCli: { event: 'done', code: 1, error: String(message) } }); },\n"
    "      status: function (payload) { send({ $fridaCli: { event: 'status', data: payload } }); }\n"
    "    };\n"
    "  }\n"
    "})();\n";
static const gchar * kReplBootstrap =
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
    "        if (typeof Java.performNow === 'function') return Java.performNow(evaluator);\n"
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
    "          sendControl('error', { id: id, message: stringifyError(error) });\n"
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
static const gchar * kStatusScript =
    "Mira.status({\n"
    "  frida_version: Frida.version,\n"
    "  pid: Process.id,\n"
    "  arch: Process.arch,\n"
    "  platform: Process.platform,\n"
    "  java_available: (typeof Java !== 'undefined' && Java.available)\n"
    "});\n"
    "Mira.done(0);\n";
static const gchar * kVersionScript =
    "send({\n"
    "  frida: Frida.version,\n"
    "  pid: Process.id,\n"
    "  arch: Process.arch,\n"
    "  platform: Process.platform\n"
    "});\n"
    "Mira.done(0);\n";

static GMainLoop * g_active_loop = NULL;
static MiraFridaRunContext * g_active_context = NULL;

static void print_usage(const char * program_name);
static gboolean parse_common_option(int argc, char ** argv, int * index, const char ** address);
static gboolean parse_timeout_option(int argc, char ** argv, int * index, guint * timeout_ms);
static gboolean parse_load_option(int argc, char ** argv, int * index, const char ** path);
static gchar * join_arguments(int argc, char ** argv, int start_index);
static gchar * wrap_batch_source(const gchar * source);
static gchar * load_script_source(const gchar * path, GError ** error);
static FridaDevice * open_remote_device(const char * address, FridaDeviceManager ** manager_out, GError ** error);
static FridaProcessList * enumerate_processes(FridaDevice * device, GError ** error);
static guint resolve_target_pid(FridaDevice * device, GError ** error);
static gboolean connect_session(MiraFridaRunContext * context, const char * address, GError ** error);
static gboolean load_script(MiraFridaRunContext * context, const gchar * name, const gchar * source, GError ** error);
static int command_status(const char * address, guint timeout_ms);
static int command_batch(const char * address, const gchar * source, guint timeout_ms, const gchar * script_name);
static int command_repl(const char * address);
static int command_version_compat(const char * address, guint timeout_ms);
static gboolean start_context_loop(MiraFridaRunContext * context, guint timeout_ms);
static void cleanup_context(MiraFridaRunContext * context);
static void print_repl_prompt(void);
static gboolean post_repl_request(MiraFridaRunContext * context, const gchar * line);
static gboolean on_repl_input(GIOChannel * channel, GIOCondition condition, gpointer user_data);
static void on_session_detached(FridaSession * session, FridaSessionDetachReason reason, FridaCrash * crash, gpointer user_data);
static void on_script_message(FridaScript * script, const gchar * message, GBytes * data, gpointer user_data);
static gboolean handle_control_message(MiraFridaRunContext * context, JsonNode * payload);
static gboolean on_timeout(gpointer user_data);
static gboolean stop_loop(gpointer user_data);
static void on_signal(int signo);
static void remove_source_if_present(guint * source_id);
static const gchar * json_object_get_optional_string(JsonObject * object, const gchar * name);
static gint json_object_get_optional_int(JsonObject * object, const gchar * name, gint fallback);
static gboolean json_object_get_optional_boolean(JsonObject * object, const gchar * name, gboolean fallback);
static void print_payload_stdout(JsonNode * payload);

int
main(int argc, char * argv[])
{
  const char * address = kDefaultAddress;
  const char * load_path = NULL;
  guint timeout_ms = kDefaultTimeoutMs;
  gboolean show_help = FALSE;
  gboolean show_status = FALSE;
  gboolean show_version_compat = FALSE;
  gboolean eval_compat = FALSE;
  gchar * inline_source = NULL;
  int i;
  int exit_code;

  frida_init();

  if (argc == 1) {
    if (isatty(STDIN_FILENO))
      return command_repl(address);
    inline_source = load_script_source("-", NULL);
    if (inline_source == NULL) {
      g_printerr("frida: failed to read script from stdin\n");
      return 2;
    }
    exit_code = command_batch(address, inline_source, timeout_ms, "stdin");
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
    if (parse_common_option(argc, argv, &i, &address))
      continue;
    if (parse_timeout_option(argc, argv, &i, &timeout_ms))
      continue;
    if (parse_load_option(argc, argv, &i, &load_path))
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

    g_printerr("frida: unsupported argument: %s\n", argv[i]);
    print_usage(argv[0]);
    return 2;
  }

  if (show_help) {
    print_usage(argv[0]);
    return 0;
  }

  if (show_status)
    return command_status(address, timeout_ms);

  if (show_version_compat)
    return command_version_compat(address, timeout_ms);

  if (eval_compat) {
    if (inline_source == NULL || *inline_source == '\0') {
      g_printerr("frida eval: missing JavaScript source\n");
      g_free(inline_source);
      return 2;
    }
    exit_code = command_batch(address, inline_source, timeout_ms, "eval");
    g_free(inline_source);
    return exit_code;
  }

  if (load_path != NULL) {
    GError * error = NULL;
    gchar * source = load_script_source(load_path, &error);
    if (source == NULL) {
      g_printerr("frida: %s\n", error != NULL ? error->message : "failed to load script");
      if (error != NULL)
        g_error_free(error);
      return 2;
    }
    exit_code = command_batch(address, source, timeout_ms, load_path);
    g_free(source);
    return exit_code;
  }

  if (!isatty(STDIN_FILENO)) {
    GError * error = NULL;
    gchar * source = load_script_source("-", &error);
    if (source == NULL) {
      g_printerr("frida: %s\n", error != NULL ? error->message : "failed to read stdin");
      if (error != NULL)
        g_error_free(error);
      return 2;
    }
    exit_code = command_batch(address, source, timeout_ms, "stdin");
    g_free(source);
    return exit_code;
  }

  return command_repl(address);
}

static void
print_usage(const char * program_name)
{
  g_print(
      "Usage:\n"
      "  %s --help\n"
      "  %s [--address HOST:PORT] [--timeout MS] --status\n"
      "  %s [--address HOST:PORT] [--timeout MS] -l FILE\n"
      "  %s [--address HOST:PORT] [--timeout MS] -l -\n"
      "  %s [--address HOST:PORT]\n"
      "\n"
      "Batch script helpers:\n"
      "  Mira.done([code])  exit current batch script\n"
      "  Mira.result(value) emit a result line\n"
      "  Mira.error(message) emit an error and exit 1\n"
      "\n"
      "REPL helpers:\n"
      "  .help             show REPL help\n"
      "  .exit             exit REPL\n",
      program_name,
      program_name,
      program_name,
      program_name,
      program_name);
}

static gboolean
parse_common_option(int argc, char ** argv, int * index, const char ** address)
{
  if (strcmp(argv[*index], "--address") == 0) {
    if (*index + 1 >= argc) {
      g_printerr("--address requires a value\n");
      return FALSE;
    }
    *address = argv[++(*index)];
    return TRUE;
  }
  return FALSE;
}

static gboolean
parse_timeout_option(int argc, char ** argv, int * index, guint * timeout_ms)
{
  if (strcmp(argv[*index], "--timeout") == 0) {
    gchar * end = NULL;
    unsigned long value;
    if (*index + 1 >= argc) {
      g_printerr("--timeout requires a value\n");
      return FALSE;
    }
    value = strtoul(argv[++(*index)], &end, 10);
    if (end == NULL || *end != '\0' || value == 0) {
      g_printerr("invalid timeout: %s\n", argv[*index]);
      return FALSE;
    }
    *timeout_ms = (guint) value;
    return TRUE;
  }
  return FALSE;
}

static gboolean
parse_load_option(int argc, char ** argv, int * index, const char ** path)
{
  if (strcmp(argv[*index], "-l") == 0) {
    if (*index + 1 >= argc) {
      g_printerr("-l requires a script path or -\n");
      return FALSE;
    }
    *path = argv[++(*index)];
    return TRUE;
  }
  return FALSE;
}

static gchar *
join_arguments(int argc, char ** argv, int start_index)
{
  GString * joined = g_string_new(NULL);
  int i;
  for (i = start_index; i < argc; i++) {
    if (i > start_index)
      g_string_append_c(joined, ' ');
    g_string_append(joined, argv[i]);
  }
  return g_string_free(joined, FALSE);
}

static gchar *
wrap_batch_source(const gchar * source)
{
  return g_strconcat(kBatchPrelude, source, "\n", NULL);
}

static gchar *
load_script_source(const gchar * path, GError ** error)
{
  gchar * contents = NULL;

  if (path != NULL && strcmp(path, "-") == 0) {
    GString * buffer = g_string_new(NULL);
    gchar chunk[4096];
    size_t n;
    while ((n = fread(chunk, 1, sizeof(chunk), stdin)) > 0)
      g_string_append_len(buffer, chunk, (gssize) n);
    if (ferror(stdin)) {
      if (error != NULL)
        g_set_error(error, G_FILE_ERROR, G_FILE_ERROR_IO, "failed to read script from stdin");
      g_string_free(buffer, TRUE);
      return NULL;
    }
    return g_string_free(buffer, FALSE);
  }

  if (!g_file_get_contents(path, &contents, NULL, error))
    return NULL;
  return contents;
}

static FridaDevice *
open_remote_device(const char * address, FridaDeviceManager ** manager_out, GError ** error)
{
  FridaDeviceManager * manager;
  FridaRemoteDeviceOptions * options;
  FridaDevice * device;

  manager = frida_device_manager_new();
  options = frida_remote_device_options_new();
  frida_remote_device_options_set_keepalive_interval(options, 0);

  device = frida_device_manager_add_remote_device_sync(manager, address, options, NULL, error);
  g_object_unref(options);

  if (device == NULL) {
    frida_unref(manager);
    return NULL;
  }

  *manager_out = manager;
  return device;
}

static FridaProcessList *
enumerate_processes(FridaDevice * device, GError ** error)
{
  return frida_device_enumerate_processes_sync(device, NULL, NULL, error);
}

static guint
resolve_target_pid(FridaDevice * device, GError ** error)
{
  FridaProcessList * processes;
  gint count;
  guint pid = 0;

  processes = enumerate_processes(device, error);
  if (processes == NULL)
    return 0;

  count = frida_process_list_size(processes);
  if (count > 0) {
    FridaProcess * process = frida_process_list_get(processes, 0);
    pid = frida_process_get_pid(process);
    g_object_unref(process);
  } else {
    g_set_error(error, FRIDA_ERROR, FRIDA_ERROR_PROCESS_NOT_FOUND, "remote Gadget reported no processes");
  }

  frida_unref(processes);
  return pid;
}

static gboolean
connect_session(MiraFridaRunContext * context, const char * address, GError ** error)
{
  context->device = open_remote_device(address, &context->manager, error);
  if (context->device == NULL)
    return FALSE;

  context->pid = resolve_target_pid(context->device, error);
  if (context->pid == 0)
    return FALSE;

  context->session = frida_device_attach_sync(context->device, context->pid, NULL, NULL, error);
  if (context->session == NULL)
    return FALSE;

  g_signal_connect(context->session, "detached", G_CALLBACK(on_session_detached), context);
  return TRUE;
}

static gboolean
load_script(MiraFridaRunContext * context, const gchar * name, const gchar * source, GError ** error)
{
  FridaScriptOptions * options;

  options = frida_script_options_new();
  frida_script_options_set_name(options, name);
  frida_script_options_set_runtime(options, FRIDA_SCRIPT_RUNTIME_DEFAULT);

  context->script = frida_session_create_script_sync(context->session, source, options, NULL, error);
  g_object_unref(options);
  if (context->script == NULL)
    return FALSE;

  g_signal_connect(context->script, "message", G_CALLBACK(on_script_message), context);
  frida_script_load_sync(context->script, NULL, error);
  return *error == NULL;
}

static int
command_status(const char * address, guint timeout_ms)
{
  FridaDeviceManager * manager = NULL;
  FridaDevice * device = NULL;
  FridaProcessList * processes = NULL;
  FridaSession * session = NULL;
  FridaScript * script = NULL;
  FridaScriptOptions * options = NULL;
  MiraFridaRunContext context;
  GError * error = NULL;
  gint count = 0;
  gint i;
  int exit_code = 0;
  gchar * wrapped_status = NULL;

  memset(&context, 0, sizeof(context));
  context.mode = MIRA_FRIDA_MODE_BATCH;
  context.exit_code = 0;
  context.timeout_ms = timeout_ms;

  device = open_remote_device(address, &manager, &error);
  if (device == NULL) {
    g_printerr("status failed: %s\n", error != NULL ? error->message : "unknown error");
    exit_code = 3;
    goto cleanup;
  }

  g_print("address: %s\n", address);
  g_print("device: %s\n", frida_device_get_name(device));
  g_print("dtype: %d\n", frida_device_get_dtype(device));

  processes = enumerate_processes(device, &error);
  if (processes == NULL) {
    g_printerr("status failed: %s\n", error != NULL ? error->message : "failed to enumerate processes");
    exit_code = 3;
    goto cleanup;
  }

  count = frida_process_list_size(processes);
  g_print("process_count: %d\n", count);
  for (i = 0; i < count; i++) {
    FridaProcess * process = frida_process_list_get(processes, i);
    g_print("  pid=%u name=%s\n", frida_process_get_pid(process), frida_process_get_name(process));
    g_object_unref(process);
  }
  if (count == 0) {
    exit_code = 3;
    goto cleanup;
  }

  {
    FridaProcess * process = frida_process_list_get(processes, 0);
    context.pid = frida_process_get_pid(process);
    g_object_unref(process);
  }

  session = frida_device_attach_sync(device, context.pid, NULL, NULL, &error);
  if (session == NULL) {
    g_printerr("status failed: %s\n", error != NULL ? error->message : "attach failed");
    exit_code = 3;
    goto cleanup;
  }
  context.session = session;
  g_signal_connect(session, "detached", G_CALLBACK(on_session_detached), &context);

  wrapped_status = wrap_batch_source(kStatusScript);
  options = frida_script_options_new();
  frida_script_options_set_name(options, "mira-frida-status");
  frida_script_options_set_runtime(options, FRIDA_SCRIPT_RUNTIME_DEFAULT);
  script = frida_session_create_script_sync(session, wrapped_status, options, NULL, &error);
  if (script == NULL) {
    g_printerr("status failed: %s\n", error != NULL ? error->message : "create script failed");
    exit_code = 4;
    goto cleanup;
  }
  context.script = script;
  g_signal_connect(script, "message", G_CALLBACK(on_script_message), &context);
  frida_script_load_sync(script, NULL, &error);
  if (error != NULL) {
    g_printerr("status failed: %s\n", error->message);
    exit_code = 4;
    goto cleanup;
  }

  if (!start_context_loop(&context, timeout_ms)) {
    if (context.interrupted) exit_code = 130;
    else if (context.timed_out) exit_code = 124;
    else if (context.exit_code != 0) exit_code = context.exit_code;
    else exit_code = 5;
    goto cleanup;
  }

  g_print("frida_version: %s\n", context.status_frida_version != NULL ? context.status_frida_version : "unknown");
  g_print("pid: %u\n", context.pid);
  g_print("arch: %s\n", context.status_arch != NULL ? context.status_arch : "unknown");
  g_print("platform: %s\n", context.status_platform != NULL ? context.status_platform : "unknown");
  g_print("java_available: %s\n", context.status_java_available ? "true" : "false");

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

static int
command_batch(const char * address, const gchar * source, guint timeout_ms, const gchar * script_name)
{
  MiraFridaRunContext context;
  GError * error = NULL;
  gchar * wrapped_source = NULL;
  int exit_code;

  memset(&context, 0, sizeof(context));
  context.mode = MIRA_FRIDA_MODE_BATCH;
  context.exit_code = 0;
  context.timeout_ms = timeout_ms;

  wrapped_source = wrap_batch_source(source);

  if (!connect_session(&context, address, &error)) {
    g_printerr("frida: %s\n", error != NULL ? error->message : "failed to connect to Gadget");
    exit_code = 3;
    goto cleanup;
  }

  if (!load_script(&context, script_name != NULL ? script_name : "mira-frida-batch", wrapped_source, &error)) {
    g_printerr("frida: %s\n", error != NULL ? error->message : "failed to load script");
    exit_code = 4;
    goto cleanup;
  }

  if (!start_context_loop(&context, timeout_ms)) {
    if (context.interrupted) exit_code = 130;
    else if (context.timed_out) exit_code = 124;
    else if (context.exit_code != 0) exit_code = context.exit_code;
    else exit_code = 5;
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

static int
command_repl(const char * address)
{
  MiraFridaRunContext context;
  GError * error = NULL;
  int exit_code;

  memset(&context, 0, sizeof(context));
  context.mode = MIRA_FRIDA_MODE_REPL;
  context.exit_code = 0;
  context.next_request_id = 1;

  if (!connect_session(&context, address, &error)) {
    g_printerr("frida: %s\n", error != NULL ? error->message : "failed to connect to Gadget");
    if (error != NULL)
      g_error_free(error);
    cleanup_context(&context);
    return 3;
  }

  if (!load_script(&context, "mira-frida-repl", kReplBootstrap, &error)) {
    g_printerr("frida: %s\n", error != NULL ? error->message : "failed to start REPL");
    if (error != NULL)
      g_error_free(error);
    cleanup_context(&context);
    return 4;
  }

  context.stdin_channel = g_io_channel_unix_new(STDIN_FILENO);
  g_io_channel_set_close_on_unref(context.stdin_channel, FALSE);
  context.stdin_source_id = g_io_add_watch(context.stdin_channel,
                                           G_IO_IN | G_IO_HUP | G_IO_ERR | G_IO_NVAL,
                                           on_repl_input,
                                           &context);

  if (!start_context_loop(&context, 0)) {
    if (context.interrupted) exit_code = 130;
    else if (context.exit_code != 0) exit_code = context.exit_code;
    else exit_code = 5;
  } else {
    exit_code = context.exit_code;
  }

  cleanup_context(&context);
  return exit_code;
}

static int
command_version_compat(const char * address, guint timeout_ms)
{
  return command_batch(address, kVersionScript, timeout_ms, "version");
}

static gboolean
start_context_loop(MiraFridaRunContext * context, guint timeout_ms)
{
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

static void
cleanup_context(MiraFridaRunContext * context)
{
  context->shutting_down = TRUE;

  remove_source_if_present(&context->stdin_source_id);
  if (context->stdin_channel != NULL) {
    g_io_channel_unref(context->stdin_channel);
    context->stdin_channel = NULL;
  }

  if (context->mode == MIRA_FRIDA_MODE_REPL) {
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
    return;
  }

  if (context->script != NULL) {
    g_signal_handlers_disconnect_by_func(context->script, G_CALLBACK(on_script_message), context);
    frida_script_unload_sync(context->script, NULL, NULL);
    frida_unref(context->script);
    context->script = NULL;
  }

  if (context->session != NULL) {
    g_signal_handlers_disconnect_by_func(context->session, G_CALLBACK(on_session_detached), context);
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
}

static void
print_repl_prompt(void)
{
  if (isatty(STDIN_FILENO)) {
    g_print("frida> ");
    fflush(stdout);
  }
}

static gboolean
post_repl_request(MiraFridaRunContext * context, const gchar * line)
{
  JsonBuilder * builder;
  JsonGenerator * generator;
  JsonNode * root;
  gchar * json;
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

static gboolean
on_repl_input(GIOChannel * channel, GIOCondition condition, gpointer user_data)
{
  MiraFridaRunContext * context = user_data;
  gchar * line = NULL;
  gsize length = 0;
  GError * error = NULL;
  GIOStatus status;

  if ((condition & (G_IO_HUP | G_IO_ERR | G_IO_NVAL)) != 0) {
    context->interrupted = TRUE;
    context->stdin_source_id = 0;
    g_idle_add(stop_loop, context);
    return G_SOURCE_REMOVE;
  }

  status = g_io_channel_read_line(channel, &line, &length, NULL, &error);
  if (status == G_IO_STATUS_ERROR) {
    context->had_error = TRUE;
    context->exit_code = 5;
    g_printerr("frida repl read error: %s\n", error != NULL ? error->message : "unknown error");
    if (error != NULL)
      g_error_free(error);
    g_free(line);
    context->stdin_source_id = 0;
    g_idle_add(stop_loop, context);
    return G_SOURCE_REMOVE;
  }

  if (status == G_IO_STATUS_EOF) {
    g_free(line);
    context->stdin_source_id = 0;
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
      print_repl_prompt();
    g_free(line);
    return G_SOURCE_CONTINUE;
  }

  if (strcmp(line, ".exit") == 0 || strcmp(line, "exit") == 0) {
    g_free(line);
    context->stdin_source_id = 0;
    g_idle_add(stop_loop, context);
    return G_SOURCE_REMOVE;
  }

  if (strcmp(line, ".help") == 0 || strcmp(line, "help") == 0) {
    g_print("REPL commands:\n  .help\n  .exit\n\nTip:\n  Type JavaScript directly. Example: Java.use('android.app.Activity')\n");
    print_repl_prompt();
    g_free(line);
    return G_SOURCE_CONTINUE;
  }

  if (context->awaiting_reply) {
    g_printerr("frida: previous evaluation is still running\n");
    print_repl_prompt();
    g_free(line);
    return G_SOURCE_CONTINUE;
  }

  post_repl_request(context, line);
  g_free(line);
  return G_SOURCE_CONTINUE;
}

static void
on_session_detached(FridaSession * session,
                    FridaSessionDetachReason reason,
                    FridaCrash * crash,
                    gpointer user_data)
{
  MiraFridaRunContext * context = user_data;
  gchar * reason_str;

  if (context != NULL && context->shutting_down)
    return;

  reason_str = g_enum_to_string(FRIDA_TYPE_SESSION_DETACH_REASON, reason);
  g_printerr("session detached: reason=%s crash=%p\n", reason_str, crash);
  g_free(reason_str);

  if (context != NULL) {
    context->had_error = TRUE;
    context->exit_code = 5;
  }
  g_idle_add(stop_loop, context);
}

static void
on_script_message(FridaScript * script,
                  const gchar * message,
                  GBytes * data,
                  gpointer user_data)
{
  MiraFridaRunContext * context = user_data;
  JsonParser * parser;
  JsonObject * root;
  const gchar * type;

  parser = json_parser_new();
  if (!json_parser_load_from_data(parser, message, -1, NULL)) {
    g_printerr("%s\n", message);
    g_object_unref(parser);
    return;
  }

  root = json_node_get_object(json_parser_get_root(parser));
  type = json_object_get_string_member(root, "type");

  if (strcmp(type, "log") == 0) {
    g_printerr("%s\n", json_object_get_string_member(root, "payload"));
  } else if (strcmp(type, "send") == 0 && json_object_has_member(root, "payload")) {
    JsonNode * payload = json_object_get_member(root, "payload");
    if (!handle_control_message(context, payload)) {
      print_payload_stdout(payload);
      if (context->mode == MIRA_FRIDA_MODE_REPL && !context->awaiting_reply)
        print_repl_prompt();
    }
  } else if (strcmp(type, "error") == 0) {
    context->had_error = TRUE;
    if (context->exit_code == 0)
      context->exit_code = 5;
    g_printerr("%s\n", message);
    g_idle_add(stop_loop, context);
  } else {
    g_printerr("%s\n", message);
  }

  g_object_unref(parser);
}

static gboolean
handle_control_message(MiraFridaRunContext * context, JsonNode * payload)
{
  JsonObject * payload_object;
  JsonNode * control_node;
  JsonObject * control_object;
  const gchar * event;

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
    const gchar * error_message = json_object_get_optional_string(control_object, "error");
    context->exit_code = json_object_get_optional_int(control_object, "code", 0);
    if (error_message != NULL && *error_message != '\0')
      g_printerr("%s\n", error_message);
    if (context->exit_code != 0)
      context->had_error = TRUE;
    g_idle_add(stop_loop, context);
    return TRUE;
  }

  if (strcmp(event, "status") == 0 && json_object_has_member(control_object, "data")) {
    JsonNode * data_node = json_object_get_member(control_object, "data");
    if (JSON_NODE_HOLDS_OBJECT(data_node)) {
      JsonObject * data_object = json_node_get_object(data_node);
      g_free(context->status_frida_version);
      context->status_frida_version = g_strdup(json_object_get_optional_string(data_object, "frida_version"));
      g_free(context->status_arch);
      context->status_arch = g_strdup(json_object_get_optional_string(data_object, "arch"));
      g_free(context->status_platform);
      context->status_platform = g_strdup(json_object_get_optional_string(data_object, "platform"));
      context->status_java_available = json_object_get_optional_boolean(data_object, "java_available", FALSE);
      context->pid = (guint) json_object_get_optional_int(data_object, "pid", (gint) context->pid);
    }
    return TRUE;
  }

  if (strcmp(event, "ready") == 0) {
    const gchar * frida_version = json_object_get_optional_string(control_object, "frida_version");
    const gchar * arch = json_object_get_optional_string(control_object, "arch");
    const gchar * platform = json_object_get_optional_string(control_object, "platform");
    gboolean java_available = json_object_get_optional_boolean(control_object, "java_available", FALSE);
    gint pid = json_object_get_optional_int(control_object, "pid", (gint) context->pid);
    g_print("connected: pid=%d frida=%s arch=%s platform=%s java=%s\n",
            pid,
            frida_version != NULL ? frida_version : "unknown",
            arch != NULL ? arch : "unknown",
            platform != NULL ? platform : "unknown",
            java_available ? "true" : "false");
    print_repl_prompt();
    return TRUE;
  }

  if (strcmp(event, "result") == 0) {
    guint id = (guint) json_object_get_optional_int(control_object, "id", -1);
    const gchar * text = json_object_get_optional_string(control_object, "text");
    if (context->mode == MIRA_FRIDA_MODE_REPL && context->awaiting_reply && id == context->pending_request_id) {
      g_print("%s\n", text != NULL ? text : "undefined");
      context->awaiting_reply = FALSE;
      context->pending_request_id = 0;
      print_repl_prompt();
    }
    return TRUE;
  }

  if (strcmp(event, "error") == 0) {
    guint id = (guint) json_object_get_optional_int(control_object, "id", -1);
    const gchar * message = json_object_get_optional_string(control_object, "message");
    if (context->mode == MIRA_FRIDA_MODE_REPL && context->awaiting_reply && id == context->pending_request_id) {
      g_printerr("%s\n", message != NULL ? message : "unknown error");
      context->awaiting_reply = FALSE;
      context->pending_request_id = 0;
      print_repl_prompt();
    } else if (message != NULL) {
      g_printerr("%s\n", message);
    }
    return TRUE;
  }

  return TRUE;
}

static gboolean
on_timeout(gpointer user_data)
{
  MiraFridaRunContext * context = user_data;
  context->timed_out = TRUE;
  context->had_error = TRUE;
  context->exit_code = 124;
  g_printerr("frida: timed out after %u ms\n", context->timeout_ms);
  return stop_loop(user_data);
}

static gboolean
stop_loop(gpointer user_data)
{
  MiraFridaRunContext * context = user_data;
  GMainLoop * loop = context != NULL ? context->loop : g_active_loop;
  if (loop != NULL && g_main_loop_is_running(loop))
    g_main_loop_quit(loop);
  return G_SOURCE_REMOVE;
}

static void
on_signal(int signo)
{
  if (g_active_context != NULL) {
    g_active_context->interrupted = TRUE;
    if (g_active_context->exit_code == 0)
      g_active_context->exit_code = 130;
  }
  if (g_active_loop != NULL)
    g_idle_add(stop_loop, g_active_context);
}

static void
remove_source_if_present(guint * source_id)
{
  GMainContext * main_context;

  if (source_id == NULL || *source_id == 0)
    return;

  main_context = g_main_context_default();
  if (g_main_context_find_source_by_id(main_context, *source_id) != NULL)
    g_source_remove(*source_id);
  *source_id = 0;
}

static const gchar *
json_object_get_optional_string(JsonObject * object, const gchar * name)
{
  if (object == NULL || !json_object_has_member(object, name))
    return NULL;
  return json_object_get_string_member(object, name);
}

static gint
json_object_get_optional_int(JsonObject * object, const gchar * name, gint fallback)
{
  if (object == NULL || !json_object_has_member(object, name))
    return fallback;
  return (gint) json_object_get_int_member(object, name);
}

static gboolean
json_object_get_optional_boolean(JsonObject * object, const gchar * name, gboolean fallback)
{
  if (object == NULL || !json_object_has_member(object, name))
    return fallback;
  return json_object_get_boolean_member(object, name);
}

static void
print_payload_stdout(JsonNode * payload)
{
  if (JSON_NODE_HOLDS_VALUE(payload) && json_node_get_value_type(payload) == G_TYPE_STRING) {
    g_print("%s\n", json_node_get_string(payload));
  } else {
    gchar * payload_str = json_to_string(payload, FALSE);
    g_print("%s\n", payload_str);
    g_free(payload_str);
  }
}
