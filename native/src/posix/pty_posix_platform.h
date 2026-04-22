#pragma once

#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct mira_pty_platform_pair {
    int master_fd;
    int slave_fd;
    char slave_name[128];
} mira_pty_platform_pair_t;

int mira_pty_platform_open_pair(mira_pty_platform_pair_t *pair);
int mira_pty_platform_open_slave(mira_pty_platform_pair_t *pair);
void mira_pty_platform_close_extra_fds(void);

#ifdef __cplusplus
}
#endif
