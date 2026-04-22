#pragma once

#include "mira/shell.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct mira_builtin_shell mira_builtin_shell_t;

mira_builtin_shell_t *mira_builtin_shell_open(const mira_shell_options_t *options);
ssize_t mira_builtin_shell_read(mira_builtin_shell_t *shell, void *buffer, size_t length);
ssize_t mira_builtin_shell_write(mira_builtin_shell_t *shell, const void *buffer, size_t length);
int mira_builtin_shell_resize(mira_builtin_shell_t *shell, int columns, int rows, int cell_width, int cell_height);
int mira_builtin_shell_wait_for(mira_builtin_shell_t *shell);
int mira_builtin_shell_close(mira_builtin_shell_t *shell);
void mira_builtin_shell_destroy(mira_builtin_shell_t *shell);

#ifdef __cplusplus
}
#endif
