# Account

> **Files:** `backend/internal/account/`, `backend/internal/daemon/machine.go`, `qml/services/session/AccountManager.qml`, `qml/components/views/Settings/AccountCard.qml`, `qml/components/content/Greeting/Greeting.qml`, `qml/components/content/parts/LoginField.qml`
> **Config:** `General.displayName` (axiom's own name for the user); the picture, real name and password are the system's
> **Related:** [Greeter runtime](greeter-runtime.md), [Lockscreen](lockscreen.md), [Polkit](polkit.md), [Testing](../testing.md) › Machine settings

Settings › General opens on the user's account: their picture, names and kind of account, and the changes a user makes to their own. Tests: `backend/internal/account`'s Go tests (a fake AccountsService on a `dbustest` bus, a scripted fake passwd in a pty).

### Reading it (`account.get`)
- With AccountsService (`org.freedesktop.Accounts`, `FindUserById` for the daemon's uid): its `RealName`, `IconFile` (when the file is there) and `AccountType` (1 is an administrator); `accounts` true.
- Without it: the GECOS name from `/etc/passwd`, administrator when the user is in `wheel`, `sudo` or `admin` (`/etc/group`), and `~/.face` as the picture.
- `AccountManager.iconUrl` adds a revision to the path, bumped with each answer, so an `Image` reloads `~/.face` after it's replaced (the same path).

### Changing it
- Every setter is the shell's only (`fromShell`), and the AccountsService ones go out with `FlagAllowInteractiveAuthorization` (polkit asks through axiom's agent when the rules want it; changing one's own data usually needs nothing).
- **Picture** (`account.setIcon`, a path from the desktop's file picker, `FilePickerManager`): the image's middle square, scaled to 256 px (`x/image/draw`, Catmull-Rom), written to `~/.face` as a PNG (atomically), then handed to AccountsService (`SetIconFile`), which keeps its own copy in `/var/lib/AccountsService/icons/` that the login screen reads (`GreetdManager.avatarOf`). An empty path removes both. PNG, JPEG, WebP, GIF and BMP up to 32 MB.
- **Real name** (`account.setRealName`): AccountsService only (changing `/etc/passwd` takes `chfn`); no `:`, `,` or new line, which GECOS can't hold.
- **Password** (`account.changePassword`, `{ current, new }`): `passwd` run in a pty of its own (`password.go`: `/dev/ptmx` and `TIOCSPTLCK`/`TIOCGPTN` through `x/sys/unix`, echo off, `LC_ALL=C` so its words can be read), answering its prompts: the current password, then the new one twice. A second "New password:" is passwd refusing the first (pam_pwquality's `BAD PASSWORD: …`), so it stops there with the reason instead of going round. The result is `{ ok, reason, message }`, reason `wrong`, `weak` (passwd's words), `mismatch` or `failed`; nothing passwd prints is logged, the passwords go only to its terminal, and a passwd that stops asking is killed after 30 s.
- The card checks the two new passwords match before asking, shakes the field that was wrong, and keeps the fields for another try.

### Where the picture shows
- Settings › General's Account card (a click on it changes it).
- The Greeting module with `showPicture` (lock screen, greeter: the user logging in's there).
- The greeter's Login module (AccountsService's copy), and the greeter's preview of it in the layouts editor (the user running the shell).
- Without AccountsService the login screen can't see `~/.face` (the greeter runs as another user), which the card says.
