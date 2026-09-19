/*
 * Guard regression check for pam_watchid.
 *
 * Every case below must be skipped: pam_sm_authenticate returns PAM_IGNORE before
 * LocalAuthentication shows anything. A case that reaches the prompt blocks, and the
 * alarm kills the run. The PAM handle is only a carrier for items, so this runs as the
 * invoking user and needs no /etc/pam.d change.
 *
 * Usage: guard_check ./pam_watchid.so
 */
#include <dlfcn.h>
#include <pwd.h>
#include <security/pam_appl.h>
#include <security/openpam.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

typedef int (*authenticate_fn)(pam_handle_t *, int, int, const char **);

static authenticate_fn authenticate;
static int failures;

static void expect_ignore(const char *name, const char *user, const char *tty, int ssh) {
    const char *argv[] = { NULL };
    struct pam_conv conv = { openpam_nullconv, NULL };
    pam_handle_t *pamh = NULL;

    if (pam_start("pam-watchid-check", user, &conv, &pamh) != PAM_SUCCESS) {
        printf("%-24s FAIL (pam_start)\n", name);
        failures++;
        return;
    }
    if (tty != NULL) {
        pam_set_item(pamh, PAM_TTY, tty);
    }
    if (ssh) {
        setenv("SSH_CONNECTION", "192.0.2.1 50000 192.0.2.2 22", 1);
        setenv("SSH_TTY", "/dev/ttys999", 1);
    } else {
        unsetenv("SSH_CONNECTION");
        unsetenv("SSH_TTY");
    }

    alarm(10);
    int rc = authenticate(pamh, PAM_SILENT, 0, argv);
    alarm(0);

    printf("%-24s %s (rc=%d)\n", name, rc == PAM_IGNORE ? "ok" : "FAIL", rc);
    if (rc != PAM_IGNORE) {
        failures++;
    }
    pam_end(pamh, rc);
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <path to pam_watchid.so>\n", argv[0]);
        return 2;
    }
    void *module = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (module == NULL || (authenticate = (authenticate_fn)dlsym(module, "pam_sm_authenticate")) == NULL) {
        fprintf(stderr, "cannot load %s: %s\n", argv[1], dlerror());
        return 2;
    }

    struct passwd *pw = getpwuid(getuid());
    const char *me = pw ? pw->pw_name : NULL;
    const char *tty = ttyname(STDIN_FILENO) ? ttyname(STDIN_FILENO) : "/dev/ttys000";

    expect_ignore("no PAM user", NULL, tty, 0);
    expect_ignore("another user", "nobody", tty, 0);
    expect_ignore("ssh session", me, tty, 1);
    expect_ignore("no tty", me, NULL, 0);
    expect_ignore("empty tty", me, "", 0);

    printf("%s\n", failures ? "guard check FAILED" : "guard check passed");
    return failures ? 1 : 0;
}
