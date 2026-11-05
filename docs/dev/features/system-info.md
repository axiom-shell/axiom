# System info

> **Files:** `backend/internal/sysinfo/`, `backend/internal/buginfo/buginfo.go`, `backend/internal/daemon/machine.go`, `qml/services/system/SystemInfoManager.qml`, `qml/components/views/Settings/SystemInfoCard.qml`, `qml/components/views/Settings/DependenciesCard.qml`, `qml/components/content/parts/ToolChecks.qml`
> **Config:** none (the System category's own cards, `x-categories` in `qml/config/schema/index.yaml`)
> **Related:** [Settings page](../core/settings-page.md), [Self-update](self-update.md), [Polkit](polkit.md), [Testing](../testing.md) › Machine settings

Settings › System opens on this machine and this axiom: what a user (or a bug report) asks first. Tests: `backend/internal/sysinfo`'s Go tests.

### The System category
- It was Maintenance: System info (`SystemInfoCard`, a category card with `first: true`, so it leads), then Date & time, axiom updates (hidden on a packaged install, `x-showIf /$packaged`), Community setups, Optional packages (`DependenciesCard`) and Saved configurations.

### What's read (`system.info`)
- `sysinfo.Reader.Read` (all from files, nothing run): the hostname (`/proc/sys/kernel/hostname`) and the pretty one and chassis (`/etc/machine-info`, else DMI's chassis type), os-release's `PRETTY_NAME`, `ID`, `LOGO` and `HOME_URL`, the kernel release, the architecture (uname), the processor's model (`/proc/cpuinfo`, the trademark marks and "N-Core Processor" dropped) and thread count, each graphics card under `/sys/class/drm` named from `pci.ids` (hwdata's; the bracketed marketing name, a short vendor), the memory total, the root filesystem's size and what's free to the user (statfs), and the boot time (`/proc/stat`'s `btime`).
- Beside it, `buginfo.Report`: the lines `axiom bug-info` prints (the tree's version, the binary, Quickshell, the compositor and monitors, the distribution, the config's state). Nothing personal is in it, so **Copy system info** copies only these lines (`SystemInfoManager.reportText`, padded as the CLI prints them), never the hostname.
- `SystemInfoManager.refresh()` asks when the card is built and on its Read again button; nothing is polled. The uptime is the boot time against the answer's time.
- The install line comes from the shell: a package (`Paths.packaged`, its version), the dev tree (`DevManager.active`), a git clone, or a copy that is neither (`SelfUpdateManager.managed`).

### Renaming (`system.setHostname`)
- Only the shell's connection may (`fromShell`). The typed name becomes the static hostname (lowercased, apostrophes dropped, other runs of characters a dash: "Travis's Laptop" → `traviss-laptop`) and, when that changes it, the pretty hostname keeps it as typed. A name with nothing left is `bad_request`.
- Both go to hostnamed with `FlagAllowInteractiveAuthorization` (`dbus.Conn.CallInteractive`), so polkit asks the user through axiom's agent; a cancelled or refused prompt is `refused` (`SystemInfoManager.errorText` says so under the name).

### Optional packages
- `ToolChecks` (shared with the onboarder's Checks page): `DependencyManager.tools` with whether each is installed (`deps.check`) and the line installing the missing ones on this distribution (`Packages.installLines`).
