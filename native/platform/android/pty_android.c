#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE 600
#endif
#if defined(__APPLE__)
#define _DARWIN_C_SOURCE
#endif

#include "mira/pty.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <util.h>
#else
#include <pty.h>
#endif

static unsigned short mira_pty_clamp_size(int value, unsigned short fallback) {
    if (value <= 0) {
        return fallback;
    }
    if (value > 65535) {
        return 65535;
    }
    return (unsigned short) value;
}

static unsigned short mira_pty_pixel_size(int cells, int cell_size) {
    if (cells <= 0 || cell_size <= 0) {
        return 0;
    }
    long pixels = (long) cells * (long) cell_size;
    if (pixels > 65535L) {
        return 65535;
    }
    return (unsigned short) pixels;
}

static int mira_pty_set_window_size(int fd, int rows, int columns, int cell_width, int cell_height) {
    struct winsize size;
    memset(&size, 0, sizeof(size));
    size.ws_row = mira_pty_clamp_size(rows, 1);
    size.ws_col = mira_pty_clamp_size(columns, 1);
    size.ws_xpixel = mira_pty_pixel_size(columns, cell_width);
    size.ws_ypixel = mira_pty_pixel_size(rows, cell_height);
    return ioctl(fd, TIOCSWINSZ, &size);
}

static int mira_pty_set_utf8_mode_fd(int fd) {
#ifdef IUTF8
    struct termios tios;
    if (tcgetattr(fd, &tios) != 0) {
        return -1;
    }
    if ((tios.c_iflag & IUTF8) == 0) {
        tios.c_iflag |= IUTF8;
        return tcsetattr(fd, TCSANOW, &tios);
    }
#else
    (void) fd;
#endif
    return 0;
}

static void mira_pty_configure_termios(int fd) {
    struct termios tios;
    if (tcgetattr(fd, &tios) != 0) {
        return;
    }
#ifdef IUTF8
    tios.c_iflag |= IUTF8;
#endif
    tios.c_iflag &= (tcflag_t) ~(IXON | IXOFF);
    (void) tcsetattr(fd, TCSANOW, &tios);
}

static void mira_pty_close_extra_fds(void) {
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

static void mira_pty_make_controlling_terminal(int slave_fd) {
    if (slave_fd < 0) {
        return;
    }
#ifdef TIOCSCTTY
    (void) ioctl(slave_fd, TIOCSCTTY, 0);
#endif
    (void) tcsetpgrp(slave_fd, getpgrp());
}

static void mira_pty_clear_environment(void) {
    extern char **environ;
    if (clearenv() == 0) {
        return;
    }
    if (environ != NULL) {
        size_t count = 0;
        for (char **cursor = environ; *cursor != NULL; ++cursor) {
            ++count;
        }

        char **names = (char **) calloc(count, sizeof(char *));
        if (names != NULL) {
            size_t name_count = 0;
            for (char **cursor = environ; *cursor != NULL; ++cursor) {
                char *equals = strchr(*cursor, '=');
                if (equals == NULL) {
                    continue;
                }
                size_t name_length = (size_t) (equals - *cursor);
                names[name_count] = (char *) malloc(name_length + 1U);
                if (names[name_count] == NULL) {
                    continue;
                }
                memcpy(names[name_count], *cursor, name_length);
                names[name_count][name_length] = '\0';
                ++name_count;
            }
            for (size_t i = 0; i < name_count; ++i) {
                if (names[i] != NULL) {
                    unsetenv(names[i]);
                    free(names[i]);
                }
            }
            free(names);
        }
    }
}

static void mira_pty_apply_environment(char *const envp[]) {
    mira_pty_clear_environment();
    if (envp == NULL) {
        return;
    }
    for (char *const *cursor = envp; *cursor != NULL; ++cursor) {
        putenv(*cursor);
    }
}

int mira_pty_platform_spawn(const char *shell_path,
                            const char *cwd,
                            char *const argv[],
                            char *const envp[],
                            int rows,
                            int columns,
                            int cell_width,
                            int cell_height,
                            int *master_fd,
                            pid_t *pid) {
    if (master_fd == NULL || pid == NULL || shell_path == NULL || shell_path[0] == '\0') {
        errno = EINVAL;
        return -1;
    }

    int ptm = -1;
    int pts = -1;

#if defined(__APPLE__)
    if (openpty(&ptm, &pts, NULL, NULL, NULL) != 0) {
        return -1;
    }
#else
    char slave_name[128];
    ptm = posix_openpt(O_RDWR | O_NOCTTY | O_CLOEXEC);
    if (ptm < 0) {
        return -1;
    }
    if (grantpt(ptm) != 0 || unlockpt(ptm) != 0 || ptsname_r(ptm, slave_name, sizeof(slave_name)) != 0) {
        int saved_errno = errno;
        close(ptm);
        errno = saved_errno;
        return -1;
    }
#endif

    mira_pty_configure_termios(ptm);

    if (mira_pty_set_window_size(ptm, rows, columns, cell_width, cell_height) != 0) {
        int saved_errno = errno;
        if (pts >= 0) {
            close(pts);
        }
        close(ptm);
        errno = saved_errno;
        return -1;
    }

    pid_t child = fork();
    if (child < 0) {
        int saved_errno = errno;
        if (pts >= 0) {
            close(pts);
        }
        close(ptm);
        errno = saved_errno;
        return -1;
    }

    if (child > 0) {
        *master_fd = ptm;
        *pid = child;
        if (pts >= 0) {
            close(pts);
        }
        return 0;
    }

    sigset_t signals_to_unblock;
    sigfillset(&signals_to_unblock);
    sigprocmask(SIG_UNBLOCK, &signals_to_unblock, NULL);

#if defined(__APPLE__)
    close(ptm);
    if (setsid() < 0) {
        _exit(1);
    }
    /* openpty() already gave us the slave end as pts. */
#else
    close(ptm);
    if (setsid() < 0) {
        _exit(1);
    }
    pts = open(slave_name, O_RDWR);
#endif
    if (pts < 0) {
        _exit(1);
    }
    mira_pty_make_controlling_terminal(pts);

    if (dup2(pts, STDIN_FILENO) < 0 || dup2(pts, STDOUT_FILENO) < 0 || dup2(pts, STDERR_FILENO) < 0) {
        _exit(1);
    }
    if (pts > STDERR_FILENO) {
        close(pts);
    }

    mira_pty_close_extra_fds();
    mira_pty_apply_environment(envp);

    if (cwd != NULL && cwd[0] != '\0' && chdir(cwd) != 0) {
        perror("chdir");
        fflush(stderr);
    }

    char *const *exec_argv = argv;
    if (exec_argv == NULL || exec_argv[0] == NULL) {
        char *default_argv[] = { (char *) shell_path, NULL };
        execvp(shell_path, default_argv);
    } else {
        execvp(shell_path, exec_argv);
    }

    perror("execvp");
    fflush(stderr);
    _exit(1);
}

ssize_t mira_pty_platform_read(int master_fd, void *buffer, size_t length) {
    if (master_fd < 0) {
        errno = EBADF;
        return -1;
    }
    while (1) {
        ssize_t result = read(master_fd, buffer, length);
        if (result < 0 && errno == EINTR) {
            continue;
        }
        if (result < 0 && errno == EIO) {
            return 0;
        }
        return result;
    }
}

ssize_t mira_pty_platform_write(int master_fd, const void *buffer, size_t length) {
    if (master_fd < 0) {
        errno = EBADF;
        return -1;
    }
    const unsigned char *cursor = (const unsigned char *) buffer;
    size_t remaining = length;
    while (remaining > 0) {
        ssize_t written = write(master_fd, cursor, remaining);
        if (written < 0 && errno == EINTR) {
            continue;
        }
        if (written < 0) {
            return -1;
        }
        if (written == 0) {
            errno = EIO;
            return -1;
        }
        cursor += written;
        remaining -= (size_t) written;
    }
    return (ssize_t) length;
}

int mira_pty_platform_resize(int master_fd, int columns, int rows, int cell_width, int cell_height) {
    if (master_fd < 0) {
        errno = EBADF;
        return -1;
    }
    return mira_pty_set_window_size(master_fd, rows, columns, cell_width, cell_height);
}

int mira_pty_platform_set_utf8_mode(int master_fd) {
    if (master_fd < 0) {
        errno = EBADF;
        return -1;
    }
    return mira_pty_set_utf8_mode_fd(master_fd);
}

int mira_pty_platform_wait_for(pid_t pid, int *status) {
    if (pid <= 0 || status == NULL) {
        errno = EINVAL;
        return -EINVAL;
    }

    while (waitpid(pid, status, 0) < 0) {
        if (errno == EINTR) {
            continue;
        }
        return -errno;
    }
    return 0;
}

int mira_pty_platform_kill(pid_t pid, int signal_number) {
    if (pid == 0) {
        errno = EINVAL;
        return -EINVAL;
    }
    if (kill(pid, signal_number) < 0) {
        if (errno == ESRCH) {
            return 0;
        }
        return -errno;
    }
    return 0;
}

int mira_pty_platform_close(int fd) {
    if (fd < 0) {
        return 0;
    }
    if (close(fd) < 0) {
        if (errno == EBADF) {
            return 0;
        }
        return -errno;
    }
    return 0;
}
