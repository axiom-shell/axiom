#!/bin/sh
#
# Description: Root's way into `axiom greeter-install` (the login screen's
#              install, update and uninstall: GreeterManager, through the
#              daemon's greeter.apply and pkexec). This file stays at the path
#              the installed polkit action (org.axiom.greeter.policy) names,
#              and an update is run by the copy it replaces, so it only hands
#              its arguments on, unchanged: to the axiom binary installed
#              beside it, else a packaged one. Never one found through PATH
#              or $AXIOM_BIN: pkexec clears the environment, and root runs
#              only a binary root owns.
# Usage:       greeter_install.sh install|update <repo> <user> [<staged bundle> [<source> [<channel> [<binary>]]]]
#              greeter_install.sh uninstall <repo> <user>
# (This helper installs the axiom binary too: the status reports it as
# binaries, so axiom runs an older installed helper's replacement instead)

here=$(dirname "$(readlink -f "$0")")
axiom="$here/../../bin/axiom"
[ -x "$axiom" ] || axiom=/usr/bin/axiom
exec "$axiom" greeter-install "$@"
