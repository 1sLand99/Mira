#pragma once

#include <stddef.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct mira_pty_process mira_pty_process_t;

/*
 * PTY 核心只暴露字节流和进程生命周期, 不负责 WebSocket、Relay 或 JSON。
 *
 * 约定:
 * - open 成功后返回一个长期有效的句柄, 由调用方持有。
 * - close 会向会话进程组发退出信号并关闭 master fd, 不主动回收句柄内存, 以便 wait_for 仍可读取退出状态。
 * - wait_for 返回 shell 退出码, 进程被信号终止时返回负信号值, 失败时返回负 errno。
 */
mira_pty_process_t *mira_pty_open(const char *shell_path,
                                  const char *cwd,
                                  char *const argv[],
                                  char *const envp[],
                                  int rows,
                                  int columns,
                                  int cell_width,
                                  int cell_height);

ssize_t mira_pty_read(mira_pty_process_t *pty, void *buffer, size_t length);
ssize_t mira_pty_write(mira_pty_process_t *pty, const void *buffer, size_t length);

int mira_pty_resize(mira_pty_process_t *pty, int columns, int rows, int cell_width, int cell_height);
int mira_pty_set_utf8_mode(mira_pty_process_t *pty);
int mira_pty_wait_for(mira_pty_process_t *pty);
int mira_pty_kill(mira_pty_process_t *pty, int signal_number);
int mira_pty_close(mira_pty_process_t *pty);
void mira_pty_destroy(mira_pty_process_t *pty);

pid_t mira_pty_pid(const mira_pty_process_t *pty);
int mira_pty_fd(const mira_pty_process_t *pty);

#ifdef __cplusplus
}
#endif
