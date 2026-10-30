# Features

[README](../README.md) · [Features](features.md) · [Installation](installation.md) · [Keybinds, IPC and launcher](usage.md) · [Configuration](configuration.md)

Everything below is one shell and one config, and everything is set from inside the shell. The screenshots come from the [example setups](configuration.md#example-setups), each built entirely with axiom's editors, so the look changes from one to the next.

**On this page:** [Bar](#bar) · [Bar styles](#bar-styles) · [Overlay](#overlay) · [Layouts editor](#the-layouts-editor) · [Edge menus](#edge-menus) · [Workspaces](#workspaces) · [Window switcher](#window-switcher-alttab) · [Your compositor](#your-compositor) · [Calendar](#calendar) · [Launcher](#launcher) · [Dock and OSD](#dock-and-osd) · [Lock screen, login screen and polkit](#lock-screen-login-screen-and-polkit) · [Theming](#theming) · [The rest](#the-rest)

## Bar

<p align="center"><img src="../assets/screenshots/desktop.webp" alt="A floating pill bar down the left, a transparent bar down the right and the dock at the top, inside the screen border"></p>

- Bars are defined in config. Have any number, on any monitor (or a copy on every one) and any edge.
- **26 widget types:**
  - Workspaces, Window, Time, NextEvent (the next event from your calendars), Media
  - Volume, Microphone, Network, Bluetooth, Battery, SystemStats, SystemTray, Notifications
  - Updates, Weather, Tailscale (with a popout of this machine, the tailnet's devices, Connect / Disconnect, account switching, the exit node and its options), KeyboardLayout, IdleInhibitor, Privacy
  - ScreenRecord (shown while recording; click to stop), Claude usage (your Claude Code plan limits, for one or more logins), Todo (open count), Pomodoro (the time left), Timer & stopwatch
  - Button (runs any command, opens a page or toggles an edge menu) and Separator
- **Popouts** grow out of the bar, or out of the screen border, with filleted corners. Widgets open theirs on hover, and Buttons can run their action on hover too.
- **The bar editor** draws each bar's sections the way the bar lays them out, on the side of the page matching the bar's edge:
  - Drag widgets in from the library, click one to edit it, and drop one on the trash can to remove it.
  - A full section scrolls.
  - It tells you, per screen, which widgets don't fit.
  - **Copy style** puts one bar's look onto others.

<p align="center"><img src="../assets/screenshots/bar-editor.webp" alt="The bar editor on a bottom powerline bar: its sections as a strip along the bottom, its settings, and the widget library" width="900"></p>

<details>
<summary><b>Popouts</b></summary>

| Calendar | Audio mixer | Notifications |
| :---: | :---: | :---: |
| <img src="../assets/screenshots/popout-calendar.webp" alt="Calendar popout with the day's events"> | <img src="../assets/screenshots/popout-audio-mixer.webp" alt="Audio mixer popout"> | <img src="../assets/screenshots/popout-notifications.webp" alt="Notifications popout"> |
| **Now playing** | **System graphs** | **Forecast** |
| <img src="../assets/screenshots/popout-now-playing.webp" alt="Now playing popout"> | <img src="../assets/screenshots/popout-system-graphs.webp" alt="System graphs popout"> | <img src="../assets/screenshots/popout-weather-forecast.webp" alt="Weather forecast popout"> |
| **Updates** | **Workspace grid** | |
| <img src="../assets/screenshots/popout-updates.webp" alt="Pending updates popout"> | <img src="../assets/screenshots/popout-workspace-grid.webp" alt="Workspace grid popout"> | |

</details>

### Bar styles

<p align="center"><img src="../assets/screenshots/bar-styles.webp" alt="Seven bars in seven styles, each in its own theme: solid filled, floating capsules with glow, powerline pills, outlined arrows, filled slants, transparent accent text with dots, and transparent underlines" width="900"></p>

Set a style once under **Settings → Look & Feel → Bar widgets**, and give any bar its own:

| | Options |
| --- | --- |
| **Background** (per bar) | solid, transparent, pills (a pill per group of widgets), floating (one bar held off the edge), floating pills |
| **Widget style** | filled, tinted, outline, underline, coloured icons, plain |
| **Shape** | rounded, capsule, slant, arrow |
| **Grouping** | separate, merged (neighbours share one background), powerline (each shape runs into the next) |
| **Ends** | shaped, pointed, rounded |
| **Separators** | none, line, dot, slash, chevron, with their thickness and margin to the widgets |
| **Accent line** | none, inner or outer edge, with an optional fade to a second color |
| **Shadow** | on or off, in the accent or any theme color |

- **Widget colors** default to **Auto**: the bar gives neighbouring widgets different accents and keeps the contrast readable. Pick a theme color for any of them instead.
- A bar can override the shared widget style, accents, shadow, font size and corner radius.
- Floating bars and pills have their own gap, and nearby pills can merge into one.
- **Translucency** (**Settings → Look & Feel → Translucency**): one opacity for every surface (bars, the screen border, popouts, menus, panels), down to 60%, with the compositor blurring behind it (Hyprland, niri, SwayFX). The blur is the compositor's own: set it from axiom under **Settings → Compositor → Window look → Blur** (size, passes, noise, …, and whether windows blur too), where window opacity lives as well, and both travel with exported and imported configs. The backdrops behind the overlay, launcher and power menu can frost the whole screen.
- **Size** (**Settings → Look & Feel → Panels & controls**), for everything outside the bars:
  - **Interface scale** (75–150 %): text and controls in the overlay, menus, popouts, the launcher, settings and notifications.
  - **Card size** (50–150 %): how big module cards are, as a share of the screen. At 100 % two cards fill its shorter side, so a monitor gets the same cards turned either way. Text keeps its size, so on a smaller screen a higher card size gives modules back their room (the overlay stays within its screen). The overlay, edge menus, desktop, lock and login screens each scale it with their own **Module size**, which zooms their text and content with the cards.
  - **Density** (compact, normal, roomy): how tightly controls, padding and gaps are packed.

  These are yours: an imported setup keeps your sizes unless you take its personal parts too.

## Overlay

<p align="center"><img src="../assets/screenshots/overlay-home.webp" alt="The overlay's Home page: Wi-Fi, quick actions, media, notifications, a clock and calendar, the mixer, network, weather and disks" width="900"></p>

- A full-screen overlay made of pages. Each page is a grid you place modules on, with gaps wherever you like. Pages have their own name and icon in the navigator.
- **42 modules**, and every one adapts to its size and shape (square, wide or tall, down to a compact figure):

  | Group | Modules |
  | --- | --- |
  | Media and sound | Now playing, Audio mixer, Volume dials |
  | System | System graphs, Top processes, Disks, Battery, Updates, Network, Tailscale |
  | Controls | Quick actions (toggles, power, pin), Screenshot, Screen recording (region or screen, with sound, recent recordings), Night light, Brightness, Bluetooth devices, Wi-Fi networks, Favourite apps |
  | Time and plans | Clock (digital, stacked or analog, in any time zone), World clocks, Clock & calendar, Calendar, Agenda, Weather |
  | Workspace | Workspaces map, Notifications |
  | Writing | Notes, AI chat |
  | Focus | Todo list, Pomodoro timer, Timer & stopwatch (one-off timers with presets, a stopwatch with laps), Focus (the timer, the todos and today's events together) |
  | Utilities | Calculator (with a keypad; math, units and currencies), Clipboard history (with pins), Emoji picker, Command output (any command's output as a card), Keybind cheat sheet |
  | Look | Theme picker, Wallpapers, Palette, Theme color swatch, Greeting |

- **Built-in pages:**
  - **Settings**, generated from the config schema
  - **Bar editor** and **Layouts** (see [the Layouts editor](#the-layouts-editor))
  - **Themes**, **Keybinds**, **Monitors** and **Calendar**

  Tool pages sit after your own in the navigator, as icons, and any of them can be hidden.
- Every page has an opener: a bar button or a keybind that opens the overlay on it, added from the editor in one click.
- **Page switcher** on the bottom or top edge, naming every page while they fit, only the current one, or none (icons only). Scroll over it to step through the pages.
- The overlay slides in from the top or bottom, or fades in, over a dimmed screen whose darkness you set (or no dimming at all).

<details>
<summary><b>Built-in pages</b></summary>

| Settings | Keybinds |
| :---: | :---: |
| <img src="../assets/screenshots/settings.webp" alt="Settings page, General category"> | <img src="../assets/screenshots/keybinds.webp" alt="Keybinds page with filter chips"> |
| **Look & Feel** | **Monitors** |
| <img src="../assets/screenshots/settings-look.webp" alt="Settings page, Look & Feel category"> | <img src="../assets/screenshots/monitors.webp" alt="The Monitors page"> |

</details>

## The Layouts editor

One editor, one grid, for everything made of modules: your **overlay pages**, your **edge menus**, the **desktop**, the **lock screen** and the **login screen**.

| A page | An edge menu |
| :---: | :---: |
| <img src="../assets/screenshots/overlay-editor.webp" alt="The Layouts editor on the Home page"> | <img src="../assets/screenshots/edge-menu-editor.webp" alt="The Layouts editor on the left edge menu, drawn against its screen edge"> |
| **The lock screen** | **The login screen** |
| <img src="../assets/screenshots/layouts-lockscreen.webp" alt="The Layouts editor on the lock screen, its grid fitted to the monitor"> | <img src="../assets/screenshots/layouts-greeter.webp" alt="The Layouts editor on the login screen"> |

- Drag a module from the library onto the grid (or click it to drop it in the first free spot): dropped into a gap it shrinks to fit, dropped onto other modules it pushes them aside (down a page, along an edge menu's edge), and you see where everything will go before you let go. Drag a module anywhere, and drag any edge or corner to resize it.
- Drag a box (or Shift/Ctrl+click) to select several modules and move them together, or drop them on the trash can to remove them.
- Undo and redo every edit (buttons, or Ctrl+Z / Ctrl+Shift+Z), and move or resize the selected module with the arrow keys (Shift to resize).
- Click a module to edit its options in the inspector, which also has steppers for its exact size.
- Edge menus are drawn against their screen edge. The desktop and the lock and login screens are fitted to each monitor: every screen gets as many grid units as fit at your card size, and modules keep to their nearest edge, so a corner stays a corner on a wider or turned screen. Each has its own Module size and an optional double grid for finer placement.
- **Desktop widgets:** modules on your desktop, under your windows, fitted inside the bars and border so they line up with your tiled windows. They sit straight on the wallpaper (or in frosted cards) and take clicks, while the empty desktop is clicked through. One layout can cover all monitors, the primary monitor, or a monitor of its own (by name, so a laptop's screen keeps its layout when you dock and undock).
- Every change shows live on your desktop (or on screen, for the lock and login screens, with **Show on screen**). **Save** keeps it, **Discard** throws it away.
- Each page and menu lists what opens it, and adds a bar button or a keybind for it.

## Edge menus

Edge menus are the overlay's other half. Every overlay module fits in them, placed on the same grid, but a menu slides out of a screen edge and leaves the rest of your desktop in view. Use them for what you want one hover away.

<p align="center"><img src="../assets/screenshots/demo-menus.webp" alt="The right menu opening beside the bar while the windows retile to make room, then a floating menu on the left" width="900"></p>

- **Floating** menus open over your windows. They grow out of the screen border or a solid bar like the popouts, or sit apart as a box.
- **Integrated** menus open outside the border and bars. They push the bars and your windows inwards, like a sidebar, and give the space back when they close.
- **Opening a menu.** Rest the pointer on its edge, or use a bar **Button**, a keybind, or IPC (`edgeMenu toggle <id>`).
- **Closing it.** A menu can close when the pointer leaves or when you click outside it. Its pin button, or the pin quick action, keeps it open.
- **Per-menu settings.** Each menu has its own:
  - edge, monitor and position along the edge
  - length: fit its modules, or take the whole edge
  - module size, padding and colors
  - hover timings

  An integrated menu can also draw a framed box along the whole edge.

| Left: media at hand (floating) | Right: chat beside the bar (integrated) | Right: the week ahead (integrated) |
| :---: | :---: | :---: |
| <img src="../assets/screenshots/menu-left.webp" alt="A floating menu on the left edge with quick actions, now playing and the audio mixer"> | <img src="../assets/screenshots/menu-right.webp" alt="An integrated menu on the right edge with quick actions, AI chat, now playing and weather"> | <img src="../assets/screenshots/menu-calendar.webp" alt="An integrated menu on the right edge with a clock, the month and the week's agenda"> |
| **Top: wallpaper and theme, dropping from a pill** | **Right: a notepad** | |
| <img src="../assets/screenshots/menu-theme.webp" alt="A floating menu under a pill bar with the wallpaper picker and theme list"> | <img src="../assets/screenshots/menu-notes.webp" alt="A floating menu on the right edge holding a note with task checkboxes"> | |

<p align="center"><img src="../assets/screenshots/menu-sidebar.webp" alt="An integrated menu pinned open on the left, with the terminals retiled beside it" width="900"></p>

## Workspaces

<p align="center"><img src="../assets/screenshots/demo-workspaces.webp" alt="Sliding right, down, left and up around a grid of workspaces" width="900"></p>

Set **Settings → Workspaces → Layout**:
- **Standard:** 1 to N, shared by every monitor.
- **Per monitor:** each monitor gets its own block of N.
- **Grid per monitor:** each monitor gets a grid (5×5 by default, up to 10×10) that you move around by row and column. On Hyprland, moving left or right slides sideways, and up or down slides vertically, whatever its own workspace animation is set to.

Then:
- **One setting, everywhere.** The bar widget, its popout, the workspace overview, the Workspaces module, the launcher's `/ws` and the `workspaces` IPC target all follow the layout.
- **A stable order.** The primary monitor comes first, so plugging one in or restarting the compositor never reshuffles which workspaces belong to which monitor. Changing the layout moves your windows to the matching place in the new one.
- **On niri**, workspaces are niri's own: a column per monitor that grows and shrinks as you use it. The bar and the overview follow it.
- **Scrolling strips.** On Hyprland, make any monitor (or every one) a strip, Hyprland's scrolling layout, horizontal or vertical. On niri, every monitor is one:
  - The bar shows the active workspace's windows in strip order, and its popout lists every workspace with its windows.
  - The mouse wheel scrolls the strip.
  - The overview shows the whole strip, off-screen columns included.
  - The **Strips** keybind preset adds swapping columns, resizing them and fitting the visible ones.
- **The overview** shows live window previews on Hyprland, and app icons elsewhere. Drag a window onto another workspace or onto a side of another window, right-drag to resize it, and middle-click to close it.
- **Keybinds included.** Presets for the grid with WASD or the arrows (add <kbd>Shift</kbd> to take the window along), or previous and next.

<p align="center"><img src="../assets/screenshots/workspace-overlay.webp" alt="The workspace overview: a 5×5 grid of workspaces with live window previews" width="900"></p>

## Window switcher (Alt+Tab)

<p align="center"><img src="../assets/screenshots/window-switcher.webp" alt="The window switcher stepping through a row of live window previews" width="900"></p>

- <kbd>Alt</kbd>+<kbd>Tab</kbd> and <kbd>Alt</kbd>+<kbd>Shift</kbd>+<kbd>Tab</kbd> step through your windows, most recently used first, on the focused monitor. Let go of <kbd>Alt</kbd> to switch, press <kbd>Esc</kbd> to stay, or click a tile.
- It only appears once you've held the keys for a moment, so a quick tap just swaps to your last window without anything drawn.
- Show windows from everywhere, from this monitor only, or from this workspace only, as live previews or app icons, at the tile size you like (**Settings → Workspaces → Window switcher**).
- The compositor holds the keys (on sway and niri, the switcher takes the keyboard while it's open), so it never misses a fast release. It's on the Keybinds page as a preset, and on any other combination you like.

## Your compositor

axiom runs on Hyprland, niri and sway, and sets up the compositor from the same settings on each (**Settings → Compositor**):
- **Keybinds** on their own page, with presets, a key recorder, and warnings for keys your own config already uses, plus a reference of every bind as a list or a keyboard, where you can press a combo to see what it does.
- **Monitors** arranged by dragging (see [the rest](#the-rest)).
- **Window look:** theme-colored borders, rounding, gaps, shadows, dimming, opacity and blur, as far as the compositor supports them. **Match axiom's shape** keeps windows in step with axiom's own shape.
- **Input:** keyboard layouts and repeat, mouse and touchpad, and the cursor theme.
- **Three modes:** applied at runtime without touching your config (the default), written to a file you include, or the whole config managed by axiom with your own files loaded after it. See [Compositor modes](installation.md#compositor-modes).

One config works on all three. Switch compositors and your bars, pages, theme and keybinds come along; settings only one compositor understands stay in the config for when you go back. What each compositor supports is in the [README](../README.md#compositors).

## Calendar

| The Calendar page | In the bar |
| :---: | :---: |
| <img src="../assets/screenshots/calendar-page.webp" alt="The Calendar page: the month with events from two calendars, the day's agenda, and the calendar switches"> | <img src="../assets/screenshots/popout-calendar.webp" alt="The bar's calendar popout with the day's events" width="300"> |

- **Sources:** your calendars from **CalDAV** accounts (iCloud, Fastmail, Nextcloud or any CalDAV server), read-only **.ics subscriptions** (holidays, shared feeds, Google's secret iCal address), and **local calendars** kept on this computer (one `.ics` file per event in `~/.local/share/axiom/calendars/`).
  - Add accounts in **Settings → Calendar**, then pick which of an account's calendars show.
  - Give any calendar a theme color in place of the server's.
  - Passwords go to your keyring, never into the config.
- **Days with events** get a dot per calendar, in the calendar popout, the **Calendar** and **Clock & calendar** modules, and the **Calendar** page.
  - Click a day to see its events, and an event to edit it.
  - Recurring events ask whether a change is for that one or all of them.
  - The **Clock & calendar** module lists the day's events where they fit. It can also show them on the lock screen, read-only.
- **The Calendar page** shows the month large, with the events in it, and switches calendars on and off.
- An **Agenda** module lists what's coming up, and the **NextEvent** bar widget shows the next event ("in 10 min · Standup").
- **Reminders** from your events show as notifications.
- **Quick add** from the launcher: `/event tomorrow 3pm Dentist`, `/event fri 9-10:30 Planning`, `/event 2026-12-24 all day Holiday`.
- **Syncing:** it syncs every few minutes while something shows a calendar (or reminders are on), and keeps a copy on disk, so it shows at once and works offline. Events never show on the login screen.

## Launcher

| Apps | Commands | Calculator | Emoji |
| :---: | :---: | :---: | :---: |
| <img src="../assets/screenshots/launcher-apps.webp" alt="Launcher searching apps"> | <img src="../assets/screenshots/launcher-commands.webp" alt="Launcher command list"> | <img src="../assets/screenshots/launcher-calc.webp" alt="Launcher converting 12 USD to euros"> | <img src="../assets/screenshots/launcher-emoji.webp" alt="Launcher emoji search"> |

- **Search:** apps (ranked by how often and how recently you use them), open windows, a calculator (math, units, currencies), the web, your clipboard history and emoji.
- **Commands:** it runs shell commands, asks your AI chat, and controls the whole shell with `/` commands. Commands that change something you can see (the theme, the volume, the wallpaper) keep the launcher open, so you can try several.
- **Placement:** floating, centred or in the upper third, or attached to the top or bottom edge like the other edge popouts. The field can sit above or below the results.

Every prefix and command is listed in [Keybinds, IPC and launcher](usage.md#launcher).

## Dock and OSD

| Dock | OSD (a column of bars) | OSD (a row of bars) |
| :---: | :---: | :---: |
| <img src="../assets/screenshots/dock.webp" alt="The dock growing out of the screen border at the top"> | <img src="../assets/screenshots/osd.webp" alt="An OSD of vertical volume bars on the right edge"> | <img src="../assets/screenshots/osd-bars.webp" alt="An OSD with brightness and microphone bars side by side"> |

**Dock:**
- **Contents:** your pinned apps, then the apps with open windows, grouped by app. A dot or line shows what's running, and a separator splits the two.
- **Using it:**
  - Click to launch or focus an app; clicking again cycles its windows.
  - Right-click for the app's menu.
  - Drag icons to reorder or pin them, or off the dock to unpin.
  - Icons magnify under the pointer, and a tooltip names each app.
- **Visibility:** always shown, shown on hover, or hidden while a window overlaps it. Running apps can count windows everywhere, on the dock's monitor only, or on its workspace only.

**OSD:**
- **Bars:** each OSD holds the bars you pick: output and microphone volume, brightness, the volume of the apps you choose, or of every other app. A change opens every OSD holding that bar.
- **Layout:** it can open on hover too, and lay its bars along the edge or across it.

**Both:**
- **Placement:** have any number, on any edge, at any position along it. Put them on a named monitor, the primary, the focused one (following focus) or every monitor.
- **Edges:** at no gap they grow out of the screen border or a solid bar, like the popouts. Held off the edge, *Auto* lines them up with a floating bar.
- **Sharing an edge:** a dock gives way to an OSD, and both give way to a floating edge menu opened on their edge.
- Edit them under **Settings → Dock & OSD**.

## Lock screen, login screen and polkit

| Lock screen | Login screen |
| :---: | :---: |
| <img src="../assets/screenshots/lockscreen.webp" alt="The lock screen: a greeting, the password field, media, a volume dial, weather, a clock and calendar, and power buttons over the blurred wallpaper"> | <img src="../assets/screenshots/greeter.webp" alt="The login screen: a greeting, the user and password fields, a clock and calendar, weather, the keyboard layout, the session picker and power buttons"> |

- **Lock screen modes:**
  - **Built-in** (`ext-session-lock`, PAM): the lock screen is laid out on the Layouts page, like an overlay page. Put a greeting, the password field, a clock, media, weather, power buttons (suspend, restart, shut down) and other display-only modules anywhere on a grid fitted to each monitor. It shows over your wallpaper (blurred and dimmed) or a color, and **Show on screen** previews it.
  - **None:** use your own locker.
- **Login screen:** optional, through greetd.
  - Laid out the same way, with a login box (pick or type the user, with their picture), a session picker, the keyboard layout, power buttons and the same display-only modules.
  - Drawn in your theme, wallpapers and monitor layout.
  - Remembers the last user and their session.
  - Installed and updated from Settings with one password prompt; changing its look needs none. See [Login screen](installation.md#login-screen-greetd).
- **Polkit prompt:** when an app asks for admin rights, the screen dims and a password prompt opens on the focused monitor, in your theme.
  - Switch which identity to authenticate as.
  - Turn it on under **Settings → Screen & Power → Authentication prompts**. axiom stops the other agent you had (hyprpolkitagent, KDE's, GNOME's), and starts it again if you turn axiom's off.

<p align="center"><img src="../assets/screenshots/polkit.webp" alt="The polkit prompt: the action, its vendor and ID, the identity, and a password field" width="500"></p>

## Theming

| Dark | Light |
| :---: | :---: |
| <img src="../assets/screenshots/themes-dark.webp" alt="Themes page in Everforest"> | <img src="../assets/screenshots/themes-light.webp" alt="Themes page in Kanagawa Lotus"> |

<p align="center"><img src="../assets/screenshots/demo-themes.webp" alt="The overlay recoloring through six themes" width="900"></p>

<p align="center"><img src="../assets/screenshots/desktop-rice.webp" alt="Rosé Pine Moon across the desktop: the bar, the dock, and kitty running fastfetch, cava and Neovim in the same palette" width="900"></p>

- **42 base16 themes**, with dark and light pairs switched by one toggle: Catppuccin, Gruvbox, Gruvbox Material, Solarized, Tokyo Night, Rosé Pine, Nord, Dracula/Alucard, Everforest, Kanagawa, One, Ayu, Nightfox (with Carbonfox, Dayfox, Nordfox and Terafox), GitHub, Oxocarbon and Submarine Sonar.
- **Generated themes** from your wallpaper, in five styles (tonal, vibrant, faithful, muted, alternate). The palette is built in OKLCH from the image's main colors, to match the contrast of the hand-made themes.
- **Light and dark** by hand, or on a schedule.
- **Wallpapers** can be set per monitor:
  - Fixed, rotating on a timer, or one for light mode and one for dark.
  - axiom draws them itself (crossfading), or uses [awww](https://github.com/LGFae/awww) for its transitions.
- **Other apps** follow the active theme too:
  - Each app is a switch under **Settings → Theme integrations**, one card per app, and gets its own `axiom` theme file.
  - Its switch shows the line that loads that file from the app's config. Copy the line, or click **Apply**, which backs your config up first.
  - Nothing else ever edits your config files.

<details>
<summary><b>Supported apps (22)</b></summary>

| Kind | Apps |
| --- | --- |
| Toolkits | GTK, Qt |
| Terminals | kitty, Alacritty, foot, WezTerm, Ghostty |
| Editors | Neovim, Helix, VS Code, Zed |
| Apps | Firefox (and its forks), Vesktop/Vencord, zathura |
| CLI tools | k9s, cava, btop, fzf, lazygit, bat/delta, Yazi, ncspot |

</details>

## The rest

| Notification | Power menu | First-run setup |
| :---: | :---: | :---: |
| <img src="../assets/screenshots/notification.webp" alt="A calendar reminder toast under the bar"> | <img src="../assets/screenshots/powermenu.webp" alt="The power menu: lock, suspend, hibernate, log out, reboot, power off"> | <img src="../assets/screenshots/onboarding.webp" alt="The first-run setup on its Look step"> |

- **Notifications:** toasts and a notification center.
  - Toasts stack from any corner of one monitor or all of them, with gaps measured from the bar or border at each edge.
  - Set how long they stay (or use the app's own timeout), keep critical ones up, and keep them quiet over fullscreen windows.
  - The history can drop an app's notifications when you focus it, or when you click or close them, and has a size and age limit.
  - Do not disturb is kept across restarts.
- **Community setups:** a gallery of looks other people built and shared ([community-setups](https://github.com/axiom-shell/community-setups)), searchable by name and tag in **Settings → Maintenance** or with `/config community`. Applying one takes its look and layout (optionally its wallpaper) and saves yours first; it never brings commands, monitors or accounts. See [Configuration](configuration.md#community-setups).
- **AI chat:** Anthropic, OpenAI, Gemini, or anything with an OpenAI-style API (Ollama, LM Studio, OpenRouter, …).
  - Replies stream in as formatted Markdown with copyable code blocks and folded thinking.
  - Saved conversations, and presets (system prompt, model, effort).
  - Image attachments: paste, screenshot a region, or drop.
  - `@` in the launcher asks a question.
  - API keys come from environment variables, your keyring or a mode-600 secrets file, never `config.json`.
- **Notes:** Markdown files in a folder you choose, edited in place with task checkboxes. A note open in two places stays in sync, and `/notes` in the launcher searches them all.
- **Todo list and pomodoro timer:** one list and one timer, on the bar, in popouts and as modules. Pick the todo a session is for; a notification marks each session's and break's end. `/todo` adds or ticks off, `/pomodoro` starts, pauses or skips.
- **Timer and stopwatch:** a one-off timer (`/timer 10m tea`, or a preset) and a stopwatch with laps, both able to run at once, on the bar, in a popout or as a module.
- **Hot corners:** rest the pointer in a screen corner to run any axiom action (the overlay or a page, the launcher, the workspace overview, lock, media, …) or your own command, per corner and monitor, with an optional delay. They work on every compositor and stay quiet over fullscreen windows.
- **Power menu:** your choice of session actions, in your order, driven by mouse or keyboard. Log out, reboot and power off ask you to confirm.
- **Monitors:** a page to arrange monitors by dragging (they snap edge to edge).
  - Set each one's mode, scale, rotation and VRR, and on Hyprland mirroring, bit depth and color management.
  - One layout is kept per set of connected monitors, and switches on its own when you plug one in.
  - **Apply** asks you to keep the change, and puts the old layout back after 15 seconds if you don't.
- **Multi-monitor:** interactive surfaces open on the primary monitor, on whichever monitor has focus, or on all of them at once.
- **First-run setup:** a guided tour, applied as you go, through:
  - the look, monitors and workspaces
  - default apps and keys
  - the compositor mode, and the optional integrations (login screen, polkit, idle)

  `/welcome` runs it again.
- **Screenshots:** a region, a window or a whole screen, picked on a frozen frame. Saved and copied, or opened in satty or swappy to annotate. Also screen recording with `wf-recorder`, with the microphone or (with `pactl`) the system's sound.
- **Brightness:** keys and an OSD bar for a laptop screen and for external monitors over DDC/CI.
- **Night light:** warmer colors on a schedule, set by axiom through the compositor (`wlsunset` on niri).
- **Idle:** axiom handles idle itself, on any compositor: dim, lock, screen off and suspend timeouts, and locking before the computer sleeps.
- **Updates:** axiom updates itself from git, following releases or `main`, with a notification or automatically, and switches to the rebuilt `axiom` binary without logging out.
- **The `axiom` command:** the shell's parent process, and a command line for scripts and keybinds.
  - Run, restart or stop the shell (`axiom run`, `axiom restart`, `axiom quit`). If the shell crashes, axiom starts it again, locked first if it was locked.
  - Drive any surface: `axiom launcher toggle`, `axiom volume up`, `axiom screenshot take region`, or any IPC target with `axiom ipc` (see [IPC](usage.md#ipc)).
  - `axiom lock` succeeds only once the lock screen is really up, so idle daemons can rely on it.
  - Read and change any setting: `axiom config get Bars`, `axiom config set Appearance.font.size 14`, `axiom config validate`.
- **Translations:** English and Japanese, with more added as a single JSON file each.

<details>
<summary><b>AI chat</b></summary>

<p align="center"><img src="../assets/screenshots/chat.webp" alt="The AI chat in an integrated edge menu, answering with a numbered list and a code block" width="420"></p>

</details>
