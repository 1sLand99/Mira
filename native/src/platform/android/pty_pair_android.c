#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE 600
#endif

#include "posix/pty_posix_platform.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int mira_pty_platform_open_pair(mira_pty_platform_pair_t *pair) {
    if (pair == NULL) {
        errno = EINVAL;
        return -1;
    }

    memset(pair, 0, sizeof(*pair));
    pair->master_fd = -1;
    pair->slave_fd = -1;

    int ptm = posix_openpt(O_RDWR | O_NOCTTY | O_CLOEXEC);
    if (ptm < 0) {
        return -1;
    }
    if (grantpt(ptm) != 0 || unlockpt(ptm) != 0 || ptsname_r(ptm, pair->slave_name, sizeof(pair->slave_name)) != 0) {
        int saved_errno = errno;
        close(ptm);
        errno = saved_errno;
        return -1;
    }

    pair->master_fd = ptm;
    return 0;
}

int mira_pty_platform_open_slave(mira_pty_platform_pair_t *pair) {
    if (pair == NULL || pair->slave_name[0] == '\0') {
        errno = EINVAL;
        return -1;
    }
    return open(pair->slave_name, O_RDWR);
}

void mira_pty_platform_close_extra_fds(void) {
    DIR *dir = opendir("/proc/self/fd");
    if (dir == NULL) {
        return;
    }

    int dir_fd = dirfd(dir);
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        char *end = NULL;
        long fd = strtol(entry->d_name, &end, 10);
        if (end == entry->d_name || *end != '\0') {
            continue;
        }
        if (fd > 2 && fd != dir_fd) {
            close((int) fd);
        }
    }

    closedir(dir);
}
