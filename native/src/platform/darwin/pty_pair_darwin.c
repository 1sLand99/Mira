#if defined(__APPLE__)
#define _DARWIN_C_SOURCE
#endif

#include "posix/pty_posix_platform.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <util.h>
#endif

int mira_pty_platform_open_pair(mira_pty_platform_pair_t *pair) {
    if (pair == NULL) {
        errno = EINVAL;
        return -1;
    }

    memset(pair, 0, sizeof(*pair));
    pair->master_fd = -1;
    pair->slave_fd = -1;

#if defined(__APPLE__)
    if (openpty(&pair->master_fd, &pair->slave_fd, NULL, NULL, NULL) != 0) {
        pair->master_fd = -1;
        pair->slave_fd = -1;
        return -1;
    }
    return 0;
#else
    errno = ENOTSUP;
    return -1;
#endif
}

int mira_pty_platform_open_slave(mira_pty_platform_pair_t *pair) {
    if (pair == NULL || pair->slave_fd < 0) {
        errno = EINVAL;
        return -1;
    }
    int slave_fd = pair->slave_fd;
    pair->slave_fd = -1;
    return slave_fd;
}

void mira_pty_platform_close_extra_fds(void) {
    long max_fd = sysconf(_SC_OPEN_MAX);
    if (max_fd < 0 || max_fd > 65536L) {
        max_fd = 1024L;
    }
    for (int fd = 3; fd < (int) max_fd; ++fd) {
        close(fd);
    }
}
