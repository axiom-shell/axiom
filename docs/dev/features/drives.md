# Removable drives

> **Files:** `services/system/DrivesManager.qml`, `components/methods/DriveInfo.qml`, `components/content/Drives/Drives.qml`, `components/content/parts/DriveRow.qml`, `components/content/parts/SecretField.qml`, `components/bar/widgets/Drives/Drives.qml`, `components/surfaces/osd/OSDStatusSource.qml`, `services/ui/LauncherCommands.qml`, `config/DrivesConfig.qml`
> **Config:** `Drives` (`DrivesConfig`: `notifications`, `onInsert`, `warnUnplugged`, `ignore`), `Apps.fileManager`; the OSD's `drive` status
> **Related:** [OSD](osd.md), [Notifications](notifications.md), [VPN](vpn.md), [Protocol](../backend/protocol.md), [D-Bus](../backend/dbus.md)

USB sticks, memory cards and discs: a notification as one is plugged in, mounting, opening, unmounting, unlocking a LUKS volume and ejecting, from the bar, an overlay card, the launcher and IPC. udisks2 does the work, reached on the system bus by the axiom daemon; Quickshell has no udisks service.

### Daemon
Package `udisks` (`backend/internal/udisks/`, wired in `daemon/drives.go`) reads UDisks2's `GetManagedObjects` once, then follows every UDisks2 signal through one subscription, so they arrive in order. It resyncs silently when UDisks2 restarts or the bus reconnects (`NameOwnerChanged`).
- **Drives shown:** `Removable || MediaRemovable || ConnectionBus ∈ {usb, sdio}`, with media, whole disk not `HintSystem`/`HintIgnore`. A card reader with no card isn't listed: inserting a card is `added`, taking it out `removed`.
- **Volumes** are filesystems and LUKS containers; partition tables, extended partitions and swap are left out, and an unlocked LUKS volume reports its cleartext's filesystem and mount points.
- **`drives.event`** comes only from signals after the sync: `added` once a volume is known or after 500 ms, `removed` only for drives that were announced.
- **Writes** are shell-only. Mounting a mounted volume answers its mount point; unmount, lock and unlock are idempotent. An unlocked container's volume is found by its own id or its cleartext's, and an unlock answers only once the state shows the cleartext (at most 2 s), so a mount right after finds it.
- **Testing:** `scripts/dev/drive-fixtures.sh up|down` sets up loop devices (`udisksctl --no-user-interaction`; LUKS passphrase `axiom-test`) for a scratch daemon run with `AXIOM_DRIVES_INCLUDE_LOOP=1`; the Go side is tested against a fake UDisks2 on `dbustest`.

### The service
`DrivesManager` (`services/system/`) holds the daemon's state and every action.
- **State:** `drives.get` after each hello, then `drives.state` on every change (the shell subscribes to every topic). `drives` leaves out the ignored ones (`DrivesConfig.ignore`, matched by `DriveInfo.ignored`: a volume's UUID or label, exactly), and they're never notified or mounted either. `available` false (udisks2 not running) shows the panel's off message.
- **Actions:** `mount`, `unmount` / `unmountAll`, `lock`, `eject` / `ejectAll`, `open`, and `askUnlock(volumeId)` then `unlock(passphrase)`. Each marks its drive in `pending` until the call answers ("Mounting…" on the row); a failure's error kind (`busy`, `not_authorized`, `wrong_passphrase`, `not_found`, `unavailable`, `failed`) becomes the row's red status (`errors`, `errorText`). The passphrase goes only in the call's body; nothing logs a call's params.
- **Open:** mounts first if needed (or asks for the passphrase, and opens once unlocked), then runs `Apps.fileManager` with the folder appended (`sh -c '<command> "$1"'`), else `xdg-open <folder>`.
- **Unlock:** `unlockRequest` is the volume whose passphrase field shows (in its `DriveRow`). The notification's Unlock sets it and opens the overlay page or edge menu holding a Drives module (`ShellManager.openModule`); with none, the field waits in the bar popout. A wrong passphrase keeps the field with `unlockError`; a right one mounts the cleartext volume when the unlock's answer says there's a filesystem in it (`mountable`: not LVM).
- **Eject:** unmounts, locks and powers off (the daemon's `drives.eject`), then says "Safe to remove" (see Who says what); `busy` warns that it's in use.
- **Created from** `shell.qml`'s `_services`, so plug-ins are noticed and IPC answers with no Drives widget or module shown.
- **Inert** on the login screen (`Paths.greeter`): nothing is fetched or listened to.

### On plug-in
Only a real `drives.event` `added` (never a drive there at login, or udisks2 restarting) runs `DrivesConfig.onInsert` (`_insert`: `ask` counts as `nothing` with notifications off, the question being a notification):
- **`ask`** (the default): a notification with Mount / Open / Ignore; an encrypted drive's says Unlock / Ignore (with notifications off, an encrypted drive is only Connected, whatever `onInsert`). Any button removes it (`dismissApp`); Mount then only mounts, said like any other mount: Open was the notification's offer.
- **`mount`**: mounts every volume it can (`_mountOnInsert`). With notifications on, a notification says where the first went (its `mount` call's `onMounted`), with Open / Eject and a `default` action (a click on it opens the folder, not the Drives module), in place of the Mounted the state would say (`_seen`'s `quiet`, spent by that mount or cleared by its failure); with them off, the Mounted the state says. While the built-in lock is up (`LockManager.builtinLocked`) nothing mounts: the drive waits in `_queued` until the unlock, Connected said meanwhile.
- **`nothing`**: Connected; the widget and module show it.

Every one of these notifications has the desktop entry `axiom-drives`: a click on one opens the Drives module (a mount's: its folder) (`registerHandler`, so it survives a reload, which the buttons' `onAction` doesn't). Unplugging or ejecting a drive clears them (`dismissApp`). "Safe to remove" and "Unplugged without ejecting" go without that entry (`_notifyKept`), so they stay until read (an ejected drive is powered off and leaves udisks at once, which would clear it).

### Who says what
Each event is said once (`_osd`: an enabled OSD shows `drive`, `OSDConfig.showsStatus`):
- **With buttons** (plug-in with `ask`, an encrypted drive, a mount on insert), with notifications on: a notification, never the OSD's card.
- **Everything else** (`_say`: Connected, Mounted, Unmounted, Safe to remove, Disconnected, eject `busy` or failed, a drive pulled while mounted with `warnUnplugged`): the OSD's card (`lastEvent`, set only then); with no OSD showing `drive`, a notification if notifications are on, else nothing.
- **Mounts and unmounts** are read from the state (`_see`, against `_seen`), so one done by a file manager is said too; not a drive's first sighting, nor an eject's unmount. An ejected drive leaving udisks as it powers off isn't Disconnected: Safe to remove stays.
- **Pulled while mounted:** still mounted in `_seen` as it leaves, and not `pending`. udisks drops a pulled drive's volumes first (still mounted), then the drive, so `_seen` keeps the ids of its mounted volumes and counts one gone from the drive as still mounted (`DriveInfo.mountedIds`); that's no Unmounted either. File managers send their own notifications too (Nemo's "Volume unmounted"); axiom can't stop those.

### What shows them
- **`DriveInfo`** (`components/methods/`, `tst_DriveInfo`): the pure parts: a drive's name (its one labelled volume's label, else vendor and model; the daemon sends no drive label) and size in decimal units ("SanDisk Ultra · 32 GB"), its icon (`usb`, `sd_card`, `album`, `hard_drive`), the volumes a list shows (a LUKS container standing for its cleartext volume, `effective`), each volume's action (`unlock`, `open`, `mount`), the volume opening the drive acts on (`pick`), and which volumes count as mounted while a pulled drive leaves (`mountedIds`).
- **Drives module and popout** (`components/content/Drives/`): a `Panel` with a `DeviceList` of `DriveRow`s, Eject all in its header; compact, the count and how many are mounted. Its keyboard is held while a passphrase field shows.
- **`DriveRow`:** a `DeviceRow` whose end button ejects (`actionIcon`). Clicking opens; on hover, unmount and lock. A drive of several volumes lists them under it, each with its own action; the passphrase field is a `SecretField`.
- **Drives bar widget:** an icon and the count, hidden with none (`hideWhenEmpty`); hovering opens the Drives popout, a left click opens the first drive, a middle click ejects them all.
- **OSD:** the `drive` status (`DrivesManager.lastEvent`) with its card ([OSD](osd.md)). In the default statuses.
- **Launcher:** `/eject [drive]` lists the drives and ejects the one picked. **IPC:** `axiom ipc drives list | mount <id> | eject <id> | ejectAll`.

### Testing
With no daemon side, the panel shows its off message. Against fixtures: a scratch daemon (`XDG_RUNTIME_DIR=<scratch>`) with `AXIOM_DRIVES_INCLUDE_LOOP=1` and `drive-fixtures.sh up`, then a nested shell (`scripts/dev/nested.sh`) on it; mount, open, unmount and eject, a LUKS unlock with a right and a wrong passphrase, and a busy unmount (a shell `cd`'d into the mount). A real USB stick, SD card and LUKS stick are a live check.
