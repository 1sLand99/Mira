#include "mira/pty.h"
#include "pty/pty_platform.h"

#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

struct mira_pty_process {
    int master_fd;
    pid_t pid;
    int wait_status;
    int wait_finished;
};

static int mira_pty_normalize_wait_status(int status) {
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    if (WIFSIGNALED(status)) {
        return -WTERMSIG(status);
    }
    return 0;
}

mira_pty_process_t *mira_pty_open(const char *shell_path,
                                  const char *cwd,
                                  char *const argv[],
                                  char *const envp[],
                                  int rows,
                                  int columns,
                                  int cell_width,
                                  int cell_height) {
    if (shell_path == NULL || shell_path[0] == '\0') {
        errno = EINVAL;
        return NULL;
    }

    mira_pty_process_t *pty = (mira_pty_process_t *) calloc(1, sizeof(*pty));
    if (pty == NULL) {
        return NULL;
    }

    int master_fd = -1;
    pid_t pid = -1;
    if (mira_pty_platform_spawn(shell_path, cwd, argv, envp, rows, columns, cell_width, cell_height, &master_fd, &pid) != 0) {
        free(pty);
        return NULL;
    }

    pty->master_fd = master_fd;
    pty->pid = pid;
    pty->wait_status = 0;
    pty->wait_finished = 0;
    return pty;
}

ssize_t mira_pty_read(mira_pty_process_t *pty, void *buffer, size_t length) {
    if (pty == NULL || buffer == NULL) {
        errno = EINVAL;
        return -1;
    }
    return mira_pty_platform_read(pty->master_fd, buffer, length);
}

ssize_t mira_pty_write(mira_pty_process_t *pty, const void *buffer, size_t length) {
    if (pty == NULL || buffer == NULL) {
        errno = EINVAL;
        return -1;
    }
    return mira_pty_platform_write(pty->master_fd, buffer, length);
}

int mira_pty_resize(mira_pty_process_t *pty, int columns, int rows, int cell_width, int cell_height) {
    if (pty == NULL) {
        errno = EINVAL;
        return -1;
    }
    if (pty->master_fd < 0) {
        return 0;
    }
    return mira_pty_platform_resize(pty->master_fd, columns, rows, cell_width, cell_height);
}

int mira_pty_set_utf8_mode(mira_pty_process_t *pty) {
    if (pty == NULL) {
        errno = EINVAL;
        return -1;
    }
    if (pty->master_fd < 0) {
        return 0;
    }
    return mira_pty_platform_set_utf8_mode(pty->master_fd);
}

int mira_pty_wait_for(mira_pty_process_t *pty) {
    if (pty == NULL) {
        errno = EINVAL;
        return -EINVAL;
    }
    if (pty->wait_finished) {
        return mira_pty_normalize_wait_status(pty->wait_status);
    }

    int status = 0;
    int rc = mira_pty_platform_wait_for(pty->pid, &status);
    if (rc != 0) {
        return rc;
    }

    pty->wait_status = status;
    pty->wait_finished = 1;
    return mira_pty_normalize_wait_status(status);
}

int mira_pty_kill(mira_pty_process_t *pty, int signal_number) {
    if (pty == NULL) {
        errno = EINVAL;
        return -1;
    }
    if (signal_number <= 0) {
        signal_number = SIGHUP;
    }
    return mira_pty_platform_kill(pty->pid, signal_number);
}

int mira_pty_close(mira_pty_process_t *pty) {
    if (pty == NULL) {
        errno = EINVAL;
        return -1;
    }
    (void) mira_pty_platform_kill(-pty->pid, SIGHUP);
    (void) mira_pty_platform_kill(pty->pid, SIGHUP);
    if (pty->master_fd < 0) {
        return 0;
    }

    int fd = pty->master_fd;
    pty->master_fd = -1;
    int rc = mira_pty_platform_close(fd);
    (void) mira_pty_platform_kill(-pty->pid, SIGCONT);
    (void) mira_pty_platform_kill(-pty->pid, SIGTERM);
    (void) mira_pty_platform_kill(pty->pid, SIGTERM);
    return rc;
}

void mira_pty_destroy(mira_pty_process_t *pty) {
    free(pty);
}

pid_t mira_pty_pid(const mira_pty_process_t *pty) {
    if (pty == NULL) {
        return -1;
    }
    return pty->pid;
}

int mira_pty_fd(const mira_pty_process_t *pty) {
    if (pty == NULL) {
        return -1;
    }
    return pty->master_fd;
}
