package com.vwww.mira;

import android.app.Application;
import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.provider.Settings;

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.io.UnsupportedEncodingException;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

final class MiraCommandRouter {
    private static final long DUMPSYS_TIMEOUT_MS = 10_000L;
    private static final long LOGCAT_TIMEOUT_MS = 8_000L;
    private static final long GETPROP_TIMEOUT_MS = 5_000L;
    private static final Set<String> DUMPSYS_ALLOWLIST = new HashSet<>(Arrays.asList(
        "activity",
        "battery",
        "batteryproperties",
        "display",
        "input",
        "power",
        "window"
    ));

    private MiraCommandRouter() {
    }

    static MiraCommandResult dispatch(Context context, String tool, List<String> argv) {
        if (tool == null) tool = "";
        if (argv == null) argv = new ArrayList<>();
        try {
            switch (tool) {
                case "am":
                case "mira-am":
                    return runAm(context, argv);
                case "mira-settings":
                    return runSettings(context, argv);
                case "mira-getprop":
                    return runGetprop(argv);
                case "mira-dumpsys":
                    return runDumpsys(argv);
                case "mira-logcat":
                    return runLogcat(argv);
                default:
                    return MiraCommandResult.error("unsupported Mira command: " + tool + "\n");
            }
        } catch (Throwable failure) {
            return MiraCommandResult.error(tool + ": " + failure.getClass().getSimpleName() + ": " + failure.getMessage() + "\n");
        }
    }

    private static MiraCommandResult runAm(Context context, List<String> argv) throws UnsupportedEncodingException {
        Application application = asApplication(context);
        List<String> effectiveArgv = argv;
        boolean help = argv.isEmpty() || "help".equals(argv.get(0)) || "--help".equals(argv.get(0)) || "--am-help".equals(argv.get(0)) || "-h".equals(argv.get(0));
        if (help) effectiveArgv = new ArrayList<>();

        ByteArrayOutputStream stdoutBuffer = new ByteArrayOutputStream();
        ByteArrayOutputStream stderrBuffer = new ByteArrayOutputStream();
        int exitCode;
        try (PrintStream stdout = new PrintStream(stdoutBuffer, true, StandardCharsets.UTF_8.name());
             PrintStream stderr = new PrintStream(stderrBuffer, true, StandardCharsets.UTF_8.name())) {
            exitCode = new com.termux.am.Am(stdout, stderr, application).run(effectiveArgv.toArray(new String[0]));
            stdout.flush();
            stderr.flush();
        }

        if (help) exitCode = 0;
        return new MiraCommandResult(
            exitCode,
            stdoutBuffer.toString(StandardCharsets.UTF_8.name()),
            stderrBuffer.toString(StandardCharsets.UTF_8.name())
        );
    }

    private static Application asApplication(Context context) {
        Context applicationContext = context.getApplicationContext();
        if (applicationContext instanceof Application) return (Application) applicationContext;
        throw new IllegalStateException("application context is not an Application");
    }

    private static MiraCommandResult runSettings(Context context, List<String> argv) {
        if (argv.isEmpty() || "help".equals(argv.get(0)) || "--help".equals(argv.get(0))) {
            return MiraCommandResult.ok("usage: mira-settings get system|secure|global KEY\n" +
                "       mira-settings list system|secure|global\n");
        }
        String action = argv.get(0);
        if ("get".equals(action)) {
            if (argv.size() != 3) return MiraCommandResult.error("usage: mira-settings get system|secure|global KEY\n");
            String value = getSetting(context, argv.get(1), argv.get(2));
            return MiraCommandResult.ok((value == null ? "null" : value) + "\n");
        }
        if ("list".equals(action)) {
            if (argv.size() != 2) return MiraCommandResult.error("usage: mira-settings list system|secure|global\n");
            return MiraCommandResult.ok(listSettings(context, argv.get(1)));
        }
        return MiraCommandResult.error("mira-settings: unsupported subcommand: " + action + "\n");
    }

    private static String getSetting(Context context, String namespace, String key) {
        switch (normalizeNamespace(namespace)) {
            case "system":
                return Settings.System.getString(context.getContentResolver(), key);
            case "secure":
                return Settings.Secure.getString(context.getContentResolver(), key);
            case "global":
                return Settings.Global.getString(context.getContentResolver(), key);
            default:
                throw new IllegalArgumentException("unsupported settings namespace: " + namespace);
        }
    }

    private static String listSettings(Context context, String namespace) {
        Uri uri;
        switch (normalizeNamespace(namespace)) {
            case "system":
                uri = Settings.System.CONTENT_URI;
                break;
            case "secure":
                uri = Settings.Secure.CONTENT_URI;
                break;
            case "global":
                uri = Settings.Global.CONTENT_URI;
                break;
            default:
                throw new IllegalArgumentException("unsupported settings namespace: " + namespace);
        }
        StringBuilder output = new StringBuilder();
        try (Cursor cursor = context.getContentResolver().query(uri, new String[] {"name", "value"}, null, null, "name")) {
            if (cursor == null) return "";
            int nameColumn = cursor.getColumnIndex("name");
            int valueColumn = cursor.getColumnIndex("value");
            while (cursor.moveToNext()) {
                output.append(cursor.getString(nameColumn)).append('=');
                String value = cursor.getString(valueColumn);
                if (value != null) output.append(value);
                output.append('\n');
            }
        }
        return output.toString();
    }

    private static MiraCommandResult runGetprop(List<String> argv) {
        if (argv.size() > 2 || (!argv.isEmpty() && ("help".equals(argv.get(0)) || "--help".equals(argv.get(0))))) {
            return MiraCommandResult.ok("usage: mira-getprop [KEY [DEFAULT]]\n");
        }
        if (argv.isEmpty()) {
            return MiraProcessRunner.run(Arrays.asList("/system/bin/getprop"), GETPROP_TIMEOUT_MS);
        }
        String key = argv.get(0);
        String fallback = argv.size() == 2 ? argv.get(1) : "";
        String value = getSystemProperty(key, fallback);
        if (value == null) {
            return MiraProcessRunner.run(Arrays.asList("/system/bin/getprop", key), GETPROP_TIMEOUT_MS);
        }
        return MiraCommandResult.ok(value + "\n");
    }

    private static String getSystemProperty(String key, String fallback) {
        try {
            Class<?> clazz = Class.forName("android.os.SystemProperties");
            Method method = clazz.getDeclaredMethod("get", String.class, String.class);
            method.setAccessible(true);
            Object value = method.invoke(null, key, fallback);
            return value == null ? fallback : String.valueOf(value);
        } catch (Throwable ignored) {
            return null;
        }
    }

    private static MiraCommandResult runDumpsys(List<String> argv) {
        if (argv.isEmpty() || "help".equals(argv.get(0)) || "--help".equals(argv.get(0))) {
            return MiraCommandResult.ok("usage: mira-dumpsys battery|display|window|activity|power|input [args...]\n");
        }
        String service = argv.get(0);
        if (!DUMPSYS_ALLOWLIST.contains(service)) {
            return MiraCommandResult.error("mira-dumpsys: service not allowed: " + service + "\n");
        }
        List<String> command = new ArrayList<>();
        command.add("/system/bin/dumpsys");
        command.add("battery".equals(service) ? "batteryproperties" : service);
        command.addAll(argv.subList(1, argv.size()));
        return MiraProcessRunner.run(command, DUMPSYS_TIMEOUT_MS);
    }

    private static MiraCommandResult runLogcat(List<String> argv) {
        if (!argv.isEmpty() && ("help".equals(argv.get(0)) || "--help".equals(argv.get(0)))) {
            return MiraCommandResult.ok("usage: mira-logcat [-d] [-t COUNT] [-T TIME] [-v FORMAT] [-s TAG] [TAG:LEVEL...]\n");
        }
        List<String> command = new ArrayList<>();
        command.add("/system/bin/logcat");
        boolean exits = false;
        boolean hasCount = false;
        boolean hasFormat = false;
        for (int i = 0; i < argv.size(); i++) {
            String arg = argv.get(i);
            if ("-c".equals(arg) || "--clear".equals(arg) || "-f".equals(arg) || "-r".equals(arg) || "-n".equals(arg) || "-G".equals(arg)) {
                return MiraCommandResult.error("mira-logcat: option not allowed: " + arg + "\n");
            }
            if ("--tag".equals(arg)) {
                command.add("-s");
                command.add(requireValue(argv, ++i, arg));
                continue;
            }
            if ("-d".equals(arg)) exits = true;
            if ("-t".equals(arg) || "-T".equals(arg)) {
                hasCount = true;
                exits = true;
            }
            if (arg.startsWith("-t") || arg.startsWith("-T")) {
                hasCount = true;
                exits = true;
            }
            if ("-v".equals(arg) || arg.startsWith("-v")) hasFormat = true;
            command.add(arg);
        }
        if (!exits) command.add("-d");
        if (!hasCount) {
            command.add("-t");
            command.add("200");
        }
        if (!hasFormat) {
            command.add("-v");
            command.add("time");
        }
        return MiraProcessRunner.run(command, LOGCAT_TIMEOUT_MS);
    }

    private static String normalizeNamespace(String namespace) {
        return namespace == null ? "" : namespace.toLowerCase(Locale.ROOT);
    }

    private static String requireValue(List<String> args, int index, String option) {
        if (index >= args.size()) {
            throw new IllegalArgumentException(option + " requires value");
        }
        return args.get(index);
    }

    private static int parseInteger(String value) {
        if (value == null) throw new NumberFormatException("null");
        if (value.startsWith("0x") || value.startsWith("0X")) {
            return (int) Long.parseLong(value.substring(2), 16);
        }
        return Integer.parseInt(value);
    }
}
