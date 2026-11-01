# packaging
reviewed: d51805b 2026-11-01  (full)

Solid: install.sh, the release/edge workflows, the AUR packages and self-update's git side match their docs, and both Checks hold. Open: three commands the shell runs (notify-send, gio, pactl) are never installed by install.sh or the packages, and a main-channel update clicked after edge moved on falls back to a go build install.sh never set up.

## Open findings
- Major: [install.sh and the AUR packages never install notify-send, gio or pactl](../../docs/dev/issues.md#installsh-and-the-aur-packages-never-install-notify-send-gio-or-pactl)
- Major: [A main-channel update applied after edge moved on needs go to rebuild the binary](../../docs/dev/issues.md#a-main-channel-update-applied-after-edge-moved-on-needs-go-to-rebuild-the-binary)
- Cleanup: [The onboarder's Checks-page purposes don't match their declared keys](../../docs/dev/issues.md#the-onboarders-checks-page-purposes-dont-match-their-declared-keys)
- Minor: `--help` prints the wrong range: release.sh's `sed -n '3,15p'` drops line 16; install.sh's reads `BASH_SOURCE[0]`, which fails under `curl | bash -s -- --help`.
- Minor: install.sh's `official_binary` runs the downloaded binary in `mktemp -d` (install.sh:541): a noexec /tmp falls back to installing go and building.
- Minor: the PKGBUILDs' removal lists miss dev-only scripts (build_binaries.sh, generate.sh, generate_emoji.py, lib/qt_paths.sh, config-usage-baseline.json, quickshell-io-allowlist.json).
- Minor: `fetch.ErrMismatch`'s "Never used" (and packaging.md's) means the file, reads as the error.

## Contract
Holds: package lists agree as far as check_packages.py checks (one-way: install.sh → Packages); install.sh's distro, COPR, compositor, autostart, official binary, dry-run and packaged paths; PKGBUILD layout and .install; release.yml and edge.yml as packaging.md says; release/fetch split; self-update channels, edgeRef, ff-only apply, blocked states, nogit, shell-only apply (Check 2); SelfUpdateManager gating and timing; onboarding open/resume, page filtering, Finish-only mode.

## Coverage
Read deeply: install.sh, Packages, DependencyManager, SelfUpdateManager, SelfUpdate, OnboardingManager, ChecksPage, selfupdate.go, daemon/selfupdate.go, release, fetch, PKGBUILDs, check_packages.py, release.sh, build_binaries.sh, edge.yml, release.yml's aur job. Outlined: SelfUpdateStatusCard, Notice, OnboardingWindow, LookPage, AppsPage, CompositorPage, StepBar, Paths, release.yml's binaries job. Skipped: the other onboarding pages (IntegrationsPage, WorkspacesPage, ExampleCard, OptionCard, BindsTable, FinishPage, WelcomePage, MonitorsPage, OnboardingPage), OnboardingCard, shell/Onboarding.qml beyond dead-member counts; no container install or makepkg run.

## History
- 2026-11-01 full: 7 findings (2 Major, 1 Cleanup, 4 Minor); recorded
