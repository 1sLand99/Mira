package com.vwww.mira;

final class MiraCommandResult {
    final int exitCode;
    final String stdout;
    final String stderr;

    MiraCommandResult(int exitCode, String stdout, String stderr) {
        this.exitCode = sanitizeExitCode(exitCode);
        this.stdout = stdout == null ? "" : stdout;
        this.stderr = stderr == null ? "" : stderr;
    }

    static MiraCommandResult ok(String stdout) {
        return new MiraCommandResult(0, stdout, "");
    }

    static MiraCommandResult error(String stderr) {
        return new MiraCommandResult(1, "", stderr == null ? "" : stderr);
    }

    private static int sanitizeExitCode(int exitCode) {
        if (exitCode < 0 || exitCode > 255) return 1;
        return exitCode;
    }
}
