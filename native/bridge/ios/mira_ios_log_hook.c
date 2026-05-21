#include "fishhook.h"
#include "mira_pty_ios_shim.h"

#include <stddef.h>
#include <stdint.h>
#include <unistd.h>

extern void mira_diagnostics_capture_write(int fd, const void *bytes, long count);

static ssize_t (*mira_original_write)(int fd, const void *buf, size_t nbyte) = NULL;
static int mira_write_hook_installed = 0;
static __thread int mira_inside_write_hook = 0;

static ssize_t mira_hooked_write(int fd, const void *buf, size_t nbyte) {
    ssize_t result;
    if (mira_original_write == NULL) {
        return -1;
    }

    result = mira_original_write(fd, buf, nbyte);
    if (mira_inside_write_hook) {
        return result;
    }

    if ((fd == STDOUT_FILENO || fd == STDERR_FILENO) && buf != NULL && result > 0) {
        mira_inside_write_hook = 1;
        size_t written = (size_t) result;
        size_t captured = written > 4096U ? 4096U : written;
        mira_diagnostics_capture_write(fd, buf, (long) captured);
        mira_inside_write_hook = 0;
    }

    return result;
}

void mira_ios_install_log_hooks(void) {
    if (mira_write_hook_installed) {
        return;
    }
    mira_write_hook_installed = 1;
    struct rebinding bindings[] = {
        {"write", mira_hooked_write, (void **) &mira_original_write},
    };
    rebind_symbols(bindings, 1);
}
