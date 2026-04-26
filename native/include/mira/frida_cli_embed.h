#ifndef MIRA_FRIDA_CLI_EMBED_H
#define MIRA_FRIDA_CLI_EMBED_H

#ifdef __cplusplus
extern "C" {
#endif

int mira_frida_cli_main(int argc, char *argv[]);
void mira_frida_cli_set_stdio(int input_fd, int output_fd, int error_fd);
void mira_frida_cli_reset_stdio(void);

#ifdef __cplusplus
}
#endif

#endif /* MIRA_FRIDA_CLI_EMBED_H */
