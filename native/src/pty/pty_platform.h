#pragma once

#include <stddef.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

int mira_pty_platform_spawn(const char *shell_path,
                            const char *cwd,
                            char *const argv[],
                            char *const envp[],
                            int rows,
                            int columns,
                            int cell_width,
                            int cell_height,
                            int *master_fd,
                            pid_t *pid);

ssize_t mira_pty_platform_read(int master_fd, void *buffer, size_t length);
ssize_t mira_pty_platform_write(int master_fd, const void *buffer, size_t length);
int mira_pty_platform_resize(int master_fd, int columns, int rows, int cell_width, int cell_height);
int mira_pty_platform_set_utf8_mode(int master_fd);
int mira_pty_platform_wait_for(pid_t pid, int *status);
int mira_pty_platform_kill(pid_t pid, int signal_number);
int mira_pty_platform_close(int fd);

#ifdef __cplusplus
}
#endif
