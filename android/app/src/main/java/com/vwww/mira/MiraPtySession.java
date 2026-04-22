package com.vwww.mira;

import java.io.Closeable;
import java.io.IOException;

public interface MiraPtySession extends Closeable {
    int getPid();

    int read(byte[] buffer) throws IOException;

    void write(byte[] data) throws IOException;

    void resize(int columns, int rows);

    default void resize(int columns, int rows, int cellWidth, int cellHeight) {
        resize(columns, rows);
    }

    default void setUtf8Mode() {
    }

    int waitFor();

    String getBackendName();

    @Override
    void close();
}
