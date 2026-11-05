#!/usr/bin/env bash
# candylock-auth — delegates to the compiled PAM helper (pam_auth).
exec "$(dirname "$0")/pam_auth"
