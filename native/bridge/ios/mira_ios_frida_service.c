#include "mira_pty_ios_shim.h"

#include "mira/frida_cli_embed.h"

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define MIRA_IOS_FRIDA_PORT 27043

typedef struct mira_ios_frida_service_state {
    pthread_mutex_t mutex;
    int started;
    int stop_requested;
    int listen_fd;
    pthread_t thread;
    char home_dir[PATH_MAX];
    char status[256];
} mira_ios_frida_service_state_t;

static mira_ios_frida_service_state_t g_frida_service = {
    .mutex = PTHREAD_MUTEX_INITIALIZER,
    .started = 0,
    .stop_requested = 0,
    .listen_fd = -1,
    .thread = 0,
    .home_dir = {0},
    .status = "idle",
};

static void mira_ios_frida_service_set_status(const char *format, ...) {
    char buffer[256];
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);

    pthread_mutex_lock(&g_frida_service.mutex);
    snprintf(g_frida_service.status, sizeof(g_frida_service.status), "%s", buffer);
    pthread_mutex_unlock(&g_frida_service.mutex);
    fprintf(stderr, "Mira iOS frida: %s\n", buffer);
}

const char *mira_ios_frida_service_status(void) {
    static char snapshot[256];
    pthread_mutex_lock(&g_frida_service.mutex);
    snprintf(snapshot, sizeof(snapshot), "%s", g_frida_service.status);
    pthread_mutex_unlock(&g_frida_service.mutex);
    return snapshot;
}

static int mira_ios_frida_make_guest_host_path(const char *guest_path,
                                               char *out,
                                               size_t out_size) {
    char home_dir[PATH_MAX];

    if (guest_path == NULL || guest_path[0] != '/') {
        errno = EINVAL;
        return -1;
    }

    pthread_mutex_lock(&g_frida_service.mutex);
    snprintf(home_dir, sizeof(home_dir), "%s", g_frida_service.home_dir);
    pthread_mutex_unlock(&g_frida_service.mutex);

    if (home_dir[0] == '\0') {
        errno = ENOENT;
        return -1;
    }

    int written = snprintf(out,
                           out_size,
                           "%s/Library/Application Support/Mira/iSH/default/data%s",
                           home_dir,
                           guest_path);
    if (written < 0 || (size_t)written >= out_size) {
        errno = ENAMETOOLONG;
        return -1;
    }
    return 0;
}

static ssize_t mira_ios_frida_recv_header(int fd, char **header_out) {
    size_t capacity = 256;
    size_t length = 0;
    char *buffer = (char *)malloc(capacity);
    if (buffer == NULL) {
        errno = ENOMEM;
        return -1;
    }

    int zero_count = 0;
    while (1) {
        char ch = '\0';
        ssize_t n = recv(fd, &ch, 1, 0);
        if (n < 0 && errno == EINTR) {
            continue;
        }
        if (n <= 0) {
            free(buffer);
            if (n == 0) {
                errno = ECONNRESET;
            }
            return -1;
        }
        if (length + 1U >= capacity) {
            capacity *= 2U;
            char *resized = (char *)realloc(buffer, capacity);
            if (resized == NULL) {
                free(buffer);
                errno = ENOMEM;
                return -1;
            }
            buffer = resized;
        }
        buffer[length++] = ch;
        if (ch == '\0') {
            zero_count++;
            if (zero_count == 2) {
                break;
            }
        } else {
            zero_count = 0;
        }
    }

    buffer[length] = '\0';
    *header_out = buffer;
    return (ssize_t)length;
}

static int mira_ios_frida_parse_argv(char *header, int *argc_out, char ***argv_out) {
    int argc = 0;
    for (char *cursor = header; *cursor != '\0'; cursor += strlen(cursor) + 1U) {
        argc++;
    }
    if (argc == 0) {
        errno = EINVAL;
        return -1;
    }

    char **argv = (char **)calloc((size_t)argc + 1U, sizeof(char *));
    if (argv == NULL) {
        errno = ENOMEM;
        return -1;
    }

    int index = 0;
    for (char *cursor = header; *cursor != '\0'; cursor += strlen(cursor) + 1U) {
        argv[index++] = cursor;
    }

    *argc_out = argc;
    *argv_out = argv;
    return 0;
}

static int mira_ios_frida_translate_argv(int argc, char **argv, char **owned_paths) {
    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "-l") != 0) {
            continue;
        }
        if (i + 1 >= argc) {
            errno = EINVAL;
            return -1;
        }

        const char *path = argv[i + 1];
        if (path == NULL || path[0] == '\0' || strcmp(path, "-") == 0) {
            ++i;
            continue;
        }
        if (path[0] != '/') {
            errno = EINVAL;
            return -1;
        }

        char translated[PATH_MAX];
        if (mira_ios_frida_make_guest_host_path(path, translated, sizeof(translated)) != 0) {
            return -1;
        }

        owned_paths[i + 1] = strdup(translated);
        if (owned_paths[i + 1] == NULL) {
            errno = ENOMEM;
            return -1;
        }
        argv[i + 1] = owned_paths[i + 1];
        ++i;
    }
    return 0;
}

static void mira_ios_frida_write_all(int fd, const char *message) {
    if (message == NULL) {
        return;
    }
    size_t remaining = strlen(message);
    const char *cursor = message;
    while (remaining > 0) {
        ssize_t written = send(fd, cursor, remaining, 0);
        if (written < 0 && errno == EINTR) {
            continue;
        }
        if (written <= 0) {
            return;
        }
        cursor += written;
        remaining -= (size_t)written;
    }
}

static void mira_ios_frida_handle_client(int fd) {
    char *header = NULL;
    char **argv = NULL;
    char **owned_paths = NULL;
    int argc = 0;

    if (mira_ios_frida_recv_header(fd, &header) < 0) {
        mira_ios_frida_write_all(fd, "frida: failed to read command header\n");
        goto cleanup;
    }
    if (mira_ios_frida_parse_argv(header, &argc, &argv) != 0) {
        mira_ios_frida_write_all(fd, "frida: invalid command header\n");
        goto cleanup;
    }

    owned_paths = (char **)calloc((size_t)argc, sizeof(char *));
    if (owned_paths == NULL) {
        mira_ios_frida_write_all(fd, "frida: out of memory\n");
        goto cleanup;
    }
    if (mira_ios_frida_translate_argv(argc, argv, owned_paths) != 0) {
        mira_ios_frida_write_all(fd, "frida: failed to translate iSH script path\n");
        goto cleanup;
    }
    if (!mira_ios_frida_loader_ensure_loaded()) {
        mira_ios_frida_write_all(fd, "frida: gadget load failed\n");
        goto cleanup;
    }

    mira_frida_cli_set_stdio(fd, fd, fd);
    int exit_code = mira_frida_cli_main(argc, argv);
    mira_frida_cli_reset_stdio();
    if (exit_code != 0) {
        fprintf(stderr, "Mira iOS frida: cli exit=%d\n", exit_code);
    }

cleanup:
    mira_frida_cli_reset_stdio();
    if (owned_paths != NULL) {
        for (int i = 0; i < argc; ++i) {
            free(owned_paths[i]);
        }
        free(owned_paths);
    }
    free(argv);
    free(header);
}

static void *mira_ios_frida_service_thread(void *unused) {
    (void)unused;

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        mira_ios_frida_service_set_status("listen socket failed: %s", strerror(errno));
        return NULL;
    }

    int yes = 1;
    (void)setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
#ifdef SO_NOSIGPIPE
    (void)setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
#endif

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(MIRA_IOS_FRIDA_PORT);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        mira_ios_frida_service_set_status("bind failed: %s", strerror(errno));
        close(fd);
        return NULL;
    }
    if (listen(fd, 4) != 0) {
        mira_ios_frida_service_set_status("listen failed: %s", strerror(errno));
        close(fd);
        return NULL;
    }

    pthread_mutex_lock(&g_frida_service.mutex);
    g_frida_service.listen_fd = fd;
    pthread_mutex_unlock(&g_frida_service.mutex);
    mira_ios_frida_service_set_status("listening on 127.0.0.1:%d", MIRA_IOS_FRIDA_PORT);

    while (1) {
        pthread_mutex_lock(&g_frida_service.mutex);
        int stop_requested = g_frida_service.stop_requested;
        pthread_mutex_unlock(&g_frida_service.mutex);
        if (stop_requested) {
            break;
        }

        int client = accept(fd, NULL, NULL);
        if (client < 0) {
            if (errno == EINTR) {
                continue;
            }
            if (errno == EBADF || errno == EINVAL) {
                break;
            }
            mira_ios_frida_service_set_status("accept failed: %s", strerror(errno));
            usleep(100000);
            continue;
        }

#ifdef SO_NOSIGPIPE
        (void)setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
#endif
        mira_ios_frida_service_set_status("client connected");
        mira_ios_frida_handle_client(client);
        shutdown(client, SHUT_RDWR);
        close(client);
        mira_ios_frida_service_set_status("listening on 127.0.0.1:%d", MIRA_IOS_FRIDA_PORT);
    }

    close(fd);
    pthread_mutex_lock(&g_frida_service.mutex);
    g_frida_service.listen_fd = -1;
    g_frida_service.started = 0;
    pthread_mutex_unlock(&g_frida_service.mutex);
    mira_ios_frida_service_set_status("stopped");
    return NULL;
}

int mira_ios_frida_service_start(const char *home_dir) {
    pthread_mutex_lock(&g_frida_service.mutex);
    if (g_frida_service.started) {
        pthread_mutex_unlock(&g_frida_service.mutex);
        return 0;
    }

    g_frida_service.started = 1;
    g_frida_service.stop_requested = 0;
    g_frida_service.listen_fd = -1;
    snprintf(g_frida_service.home_dir,
             sizeof(g_frida_service.home_dir),
             "%s",
             home_dir == NULL ? "" : home_dir);
    pthread_mutex_unlock(&g_frida_service.mutex);

    int err = pthread_create(&g_frida_service.thread, NULL, mira_ios_frida_service_thread, NULL);
    if (err != 0) {
        pthread_mutex_lock(&g_frida_service.mutex);
        g_frida_service.started = 0;
        pthread_mutex_unlock(&g_frida_service.mutex);
        mira_ios_frida_service_set_status("thread create failed: %s", strerror(err));
        errno = err;
        return -1;
    }
    pthread_detach(g_frida_service.thread);
    return 0;
}

void mira_ios_frida_service_stop(void) {
    pthread_mutex_lock(&g_frida_service.mutex);
    g_frida_service.stop_requested = 1;
    int fd = g_frida_service.listen_fd;
    pthread_mutex_unlock(&g_frida_service.mutex);
    if (fd >= 0) {
        shutdown(fd, SHUT_RDWR);
        close(fd);
    }
}
