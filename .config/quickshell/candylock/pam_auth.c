/*
 * pam_auth.c — minimal PAM authenticator for candylock
 * Reads password from stdin, authenticates via PAM "login" service.
 * Compile: gcc -O2 -o pam_auth pam_auth.c -lpam
 * Usage:   echo "$PASSWORD" | ./pam_auth
 * Returns: 0 on success, 1 on failure
 */
#include <security/pam_appl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char pw[512];

static int conv(int num, const struct pam_message **msg,
                struct pam_response **resp, void *data) {
    struct pam_response *r = calloc(num, sizeof *r);
    if (!r) return PAM_BUF_ERR;
    for (int i = 0; i < num; i++) {
        int style = msg[i]->msg_style;
        if (style == PAM_PROMPT_ECHO_OFF || style == PAM_PROMPT_ECHO_ON)
            r[i].resp = strdup(pw);
    }
    *resp = r;
    return PAM_SUCCESS;
}

int main(void) {
    const char *user = getenv("USER");
    if (!user) return 1;

    if (!fgets(pw, (int)sizeof pw, stdin)) return 1;
    size_t n = strlen(pw);
    if (n && pw[n - 1] == '\n') pw[--n] = '\0';

    struct pam_conv pc = {conv, NULL};
    pam_handle_t *ph = NULL;
    if (pam_start("hyprlock", user, &pc, &ph) != PAM_SUCCESS) return 1;

    int ok = pam_authenticate(ph, 0);
    pam_end(ph, ok);
    memset(pw, 0, sizeof pw);
    return ok == PAM_SUCCESS ? 0 : 1;
}
