package com.vwww.mira;

import java.io.IOException;

public final class MiraPtyProcess implements MiraPtySession {
    static {
        System.loadLibrary("mira_pty");
    }

    private final long handle;
    private final int pid;
    private volatile boolean closed;

    public MiraPtyProcess(MiraPtyLaunchSpec spec) {
        this(spec.getShellPath(), spec.getCwd(), spec.getArgs(), spec.getEnv(), spec.getRows(), spec.getColumns());
    }

    public MiraPtyProcess(String shellPath, String cwd, String[] args, String[] env, int rows, int columns) {
        handle = nativeOpen(shellPath, cwd, args, env, rows, columns);
        if (handle == 0) throw new IllegalStateException("native PTY open returned null handle");
        pid = nativePid(handle);
        if (pid <= 0) {
            nativeClose(handle);
            throw new IllegalStateException("native PTY open returned invalid pid");
        }
    }

    @Override
    public int getPid() {
        return pid;
    }

    @Override
    public int read(byte[] buffer) throws IOException {
        if (closed) return -1;
        return nativeRead(handle, buffer, buffer == null ? 0 : buffer.length);
    }

    @Override
    public void write(byte[] data) throws IOException {
        if (closed) throw new IOException("PTY is closed");
        nativeWrite(handle, data, data == null ? 0 : data.length);
    }

    @Override
    public void resize(int columns, int rows) {
        if (columns <= 0 || rows <= 0 || closed) return;
        nativeResize(handle, columns, rows);
    }

    @Override
    public int waitFor() {
        if (handle == 0) return -1;
        return nativeWaitFor(handle);
    }

    @Override
    public String getBackendName() {
        return "native";
    }

    @Override
    public void close() {
        if (closed) return;
        closed = true;
        nativeClose(handle);
    }

    private static native long nativeOpen(String shellPath, String cwd, String[] args, String[] env, int rows, int columns);

    private static native int nativeRead(long handle, byte[] buffer, int length) throws IOException;

    private static native void nativeWrite(long handle, byte[] data, int length) throws IOException;

    private static native void nativeResize(long handle, int columns, int rows);

    private static native int nativeWaitFor(long handle);

    private static native int nativePid(long handle);

    private static native void nativeKill(long handle, int signalNumber);

    private static native void nativeClose(long handle);
}
