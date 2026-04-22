package com.vwww.mira;

import android.os.SystemClock;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;

final class MiraProcessRunner {
    private static final int MAX_OUTPUT_BYTES = 1024 * 1024;

    private MiraProcessRunner() {
    }

    static MiraCommandResult run(List<String> argv, long timeoutMs) {
        if (argv == null || argv.isEmpty()) {
            return MiraCommandResult.error("empty command\n");
        }
        Process process;
        try {
            process = new ProcessBuilder(argv).start();
        } catch (IOException failure) {
            return MiraCommandResult.error(argv.get(0) + ": " + failure.getMessage() + "\n");
        }

        LimitedOutput stdout = new LimitedOutput();
        LimitedOutput stderr = new LimitedOutput();
        Thread stdoutThread = new Thread(() -> readStream(process.getInputStream(), stdout), "MiraCmdStdout");
        Thread stderrThread = new Thread(() -> readStream(process.getErrorStream(), stderr), "MiraCmdStderr");
        stdoutThread.start();
        stderrThread.start();

        int exitCode;
        long deadline = SystemClock.uptimeMillis() + Math.max(timeoutMs, 1000L);
        while (true) {
            try {
                exitCode = process.exitValue();
                break;
            } catch (IllegalThreadStateException stillRunning) {
                if (SystemClock.uptimeMillis() >= deadline) {
                    process.destroy();
                    try {
                        Thread.sleep(100L);
                    } catch (InterruptedException interrupted) {
                        Thread.currentThread().interrupt();
                    }
                    try {
                        exitCode = process.exitValue();
                    } catch (IllegalThreadStateException ignored) {
                        exitCode = 124;
                    }
                    stderr.appendText("\ncommand timed out\n");
                    break;
                }
                try {
                    Thread.sleep(50L);
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                    process.destroy();
                    return new MiraCommandResult(130, stdout.toText(), stderr.toText() + "\ncommand interrupted\n");
                }
            }
        }

        joinQuietly(stdoutThread);
        joinQuietly(stderrThread);
        return new MiraCommandResult(exitCode, stdout.toText(), stderr.toText());
    }

    private static void readStream(InputStream input, LimitedOutput output) {
        byte[] buffer = new byte[8192];
        try {
            int read;
            while ((read = input.read(buffer)) != -1) {
                output.write(buffer, 0, read);
            }
        } catch (IOException failure) {
            output.appendText("\nread failed: " + failure.getMessage() + "\n");
        }
    }

    private static void joinQuietly(Thread thread) {
        try {
            thread.join(500L);
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
        }
    }

    private static final class LimitedOutput {
        private final ByteArrayOutputStream output = new ByteArrayOutputStream();
        private int droppedBytes;

        synchronized void write(byte[] buffer, int offset, int length) {
            int remaining = MAX_OUTPUT_BYTES - output.size();
            if (remaining > 0) {
                int accepted = Math.min(remaining, length);
                output.write(buffer, offset, accepted);
                droppedBytes += length - accepted;
            } else {
                droppedBytes += length;
            }
        }

        synchronized void appendText(String text) {
            if (text == null || text.isEmpty()) return;
            byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
            write(bytes, 0, bytes.length);
        }

        synchronized String toText() {
            String text = new String(output.toByteArray(), StandardCharsets.UTF_8);
            if (droppedBytes > 0) {
                text += "\n[truncated " + droppedBytes + " bytes]\n";
            }
            return text;
        }
    }
}
