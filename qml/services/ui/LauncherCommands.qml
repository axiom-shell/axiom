pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.compositor
import qs.services.session
import qs.services.system
import qs.services.apps

/*
 * The launcher's slash commands, one per shell feature. LauncherManager
 * filters and runs them; each entry is
 *   { name, aliases, glyph, description, usage,
 *     needsArg,   Enter without an argument completes "/name " instead
 *     confirm,    asks for a second Enter first (what can't be undone:
 *                 destructive session actions, clearing notifications,
 *                 installing an update)
 *     available() whether it's listed at all
 *     status()    current state, shown on the command's row
 *     options(arg) completion rows [{ title, subtitle, glyph, image, value,
 *                  matched: already matched to arg, so not scored by title }]
 *     run(arg, value) value is the picked option's, else undefined;
 *                     returns false to keep the launcher open (where the
 *                     change shows, so several can be tried), or a string
 *                     to search for instead }
 * Descriptions are read when listed, so they follow the language.
 */
QtObject {
  id: root

  // The /config entry's browser: settings, saved configs, examples and
  // community setups
  property LauncherConfigBrowser _config: LauncherConfigBrowser {}

  readonly property var list: [
    // --- Session ---
    root._action("lock", "lock", ["lock-screen"], "Lock the screen"), root._action("suspend", "suspend", ["sleep"], "Suspend to RAM"), root._action("hibernate", "hibernate", [], "Hibernate to disk"), root._action("logout", "logout", ["exit"], "End the session"), root._action("reboot", "reboot", ["restart"], "Restart the computer"), root._action("poweroff", "poweroff", ["shutdown"], "Turn the computer off"),
    // --- Surfaces ---
    root._action("power", "powerMenu", ["powermenu"], "Open the power menu"), root._action("workspaces", "workspaceOverview", ["overview"], "Open or close the workspace overview"),
    {
      name: "overlay",
      aliases: ["page"],
      glyph: "dashboard",
      usage: "[page]",
      description: () => I18n.tr("Open the overlay, or one of its pages"),
      options: () => root._overlayPages(),
      run: (arg, value) => {
        const page = value ?? arg.trim();
        if (page === "")
          ShellManager.toggleOverlay();
        else
          ShellManager.openOverlayPage(page);
      }
    },
    root._page("settings", ["prefs", "options"], "Settings", "Open the settings"), root._page("themes", [], "Themes", "Open the themes page"), root._page("bar", ["bareditor"], "BarEditor", "Open the bar editor"), root._page("keybinds", ["keys", "shortcuts"], "Keybinds", "Show the keybinds"), root._page("rules", ["windowrules", "window-rules"], "WindowRules", "Edit the window rules"), root._page("rule", ["newrule"], "WindowRules", "Make a rule for the focused window", () => WindowRulesManager.newFromFocused()), root._page("layouts", ["editor", "overlay-editor"], "Layouts", "Edit the overlay pages and menus", () => OverlayManager.editPages()), root._page("menus", ["edge-menus", "menu-editor"], "Layouts", "Edit the menus", () => OverlayManager.editMenus()), root._page("monitors", ["displays", "screens"], "Monitors", "Arrange and set up monitors"), root._page("widgets", ["custom-widgets", "waybar"], "CustomWidgets", "Make widgets from scripts"),
    // --- Appearance ---
    {
      name: "theme",
      aliases: ["colors"],
      glyph: "palette",
      usage: "<theme>",
      needsArg: true,
      description: () => I18n.tr("Switch the color theme"),
      status: () => ThemeManager.currentFamily?.label ?? ThemeManager.activeTheme,
      options: () => ThemeManager.themeFamilies.map(family => ({
              title: family.label,
              subtitle: family === ThemeManager.currentFamily ? I18n.tr("Current") : family.generated ? I18n.tr("Generated") : family.community ? I18n.tr("From a community setup") : family.dark && family.light ? I18n.tr("Dark and light") : family.dark ? I18n.tr("Dark") : I18n.tr("Light"),
              value: family
            })),
      run: (arg, value) => {
        if (value)
          ThemeManager.applyFamily(value);
        return false;
      }
    },
    Object.assign(root._action("dark", "darkMode", [], "Use the theme's dark variant", "open"), {
      glyph: "clear_night",
      status: undefined
    }), Object.assign(root._action("light", "darkMode", [], "Use the theme's light variant", "close"), {
      glyph: "sunny",
      status: undefined
    }), Object.assign(root._action("mode", "darkMode", ["darkmode"], "Toggle light and dark"), {
      status: () => Appearance.darkMode ? I18n.tr("Dark") : I18n.tr("Light")
    }),
    {
      name: "wallpaper",
      aliases: ["wall", "bg"],
      glyph: "image",
      usage: "<file>",
      needsArg: true,
      description: () => I18n.tr("Set the focused monitor's wallpaper"),
      options: () => root._wallpapers(),
      run: (arg, value) => {
        if (value === "random")
          WallpaperManager.random();
        else if (value)
          WallpaperManager.pick(value, "", "");
        return false;
      }
    },
    {
      name: "transition",
      aliases: ["wallpapertransition", "preview"],
      glyph: "animation",
      usage: "<transition>",
      needsArg: true,
      description: () => I18n.tr("Try a wallpaper transition on the next wallpaper"),
      options: () => root._transitions(),
      run: (arg, value) => {
        if (value)
          WallpaperManager.preview(value);
        return false;
      }
    },
    Object.assign(root._action("nextwallpaper", "nextWallpaper", ["nextwall", "rotate"], "Next wallpaper of the rotation"), {
      glyph: "shuffle"
    }),
    {
      name: "generate",
      aliases: ["pywal"],
      glyph: "auto_fix",
      description: () => I18n.tr("Generate themes from the current wallpaper"),
      status: () => ThemeManager.isGenerating ? I18n.tr("Generating…") : "",
      run: () => {
        const monitor = ShellManager.targetFor(LauncherConfig.screen);
        const wallpaper = ThemeManager.wallpaperFor(monitor);
        if (wallpaper)
          ThemeManager.generateThemesFromWallpaper(wallpaper);
      }
    },
    // --- Audio & media ---
    {
      name: "volume",
      aliases: ["vol"],
      glyph: "volume_up",
      usage: "<0-100 | +n | -n>",
      needsArg: true,
      description: () => I18n.tr("Set the output volume"),
      status: () => AudioManager.muted ? I18n.tr("Muted") : Math.round(AudioManager.volume * 100) + "%",
      run: arg => {
        const match = arg.trim().match(/^([+-]?)(\d+)%?$/);
        if (match) {
          const amount = parseInt(match[2]) / 100;
          if (match[1] === "+")
            AudioManager.increaseVolume(amount);
          else if (match[1] === "-")
            AudioManager.decreaseVolume(amount);
          else
            AudioManager.setVolume(amount);
        }
        return false;
      }
    },
    Object.assign(root._action("mute", "toggleMute", [], "Mute or unmute the output"), {
      glyph: "volume_off"
    }), Object.assign(root._action("mic", "toggleMicMute", ["microphone"], "Mute or unmute the microphone"), {
      glyph: "mic"
    }), root._device("output", ["sink", "speakers"], "speaker", "Choose the audio output", () => AudioManager.sinks, () => AudioManager.defaultSink), root._device("input", ["source"], "mic", "Choose the audio input", () => AudioManager.sources, () => AudioManager.defaultSource), root._media("play", ["pause"], "Play or pause", "mediaPlayPause"), root._media("next", ["skip"], "Next track", "mediaNext"), root._media("prev", ["previous", "back"], "Previous track", "mediaPrevious"),
    // --- Connectivity ---
    root._switch("wifi", "wifi", ["wlan"], "Turn wifi on or off"), root._switch("bluetooth", "bluetooth", ["bt"], "Turn bluetooth on or off"), root._switch("airplane", "airplane", ["flight", "airplane-mode"], "Turn airplane mode on or off"),
    {
      name: "vpn",
      aliases: ["wireguard", "openvpn"],
      glyph: "vpn_lock",
      usage: "[name]",
      description: () => I18n.tr("Connect or disconnect a VPN"),
      available: () => VpnManager.rows.length > 0,
      status: () => VpnManager.primary?.name ?? I18n.tr("Off"),
      options: () => VpnManager.rows.map(row => ({
              title: row.name,
              subtitle: VpnManager.statusText(row),
              glyph: VpnManager.kindIcon(row.kind),
              value: row.id
            })),
      run: (arg, value) => {
        const wanted = String(arg ?? "").trim().toLowerCase();
        const row = value ? VpnManager.rowById(value) : wanted !== "" ? VpnManager.rows.find(r => r.name.toLowerCase().startsWith(wanted)) : null;
        if (row)
          VpnManager.toggle(row);
        else if (wanted === "")
          VpnManager.toggleLast();
        return false;
      }
    },
    {
      name: "connect",
      aliases: ["disconnect", "device"],
      glyph: "bluetooth_connected",
      usage: "<device>",
      needsArg: true,
      description: () => I18n.tr("Connect or disconnect a paired bluetooth device"),
      available: () => BluetoothManager.enabled,
      options: () => BluetoothManager.pairedDevices.map(device => ({
              title: BluetoothManager.deviceLabel(device),
              subtitle: BluetoothManager.deviceStatus(device),
              glyph: BluetoothManager.deviceIcon(device),
              value: device
            })),
      run: (arg, value) => {
        if (value)
          BluetoothManager.toggleDevice(value);
      }
    },
    {
      name: "eject",
      aliases: ["drives", "unmount"],
      glyph: "eject",
      usage: "[drive]",
      description: () => I18n.tr("Eject a removable drive"),
      available: () => !Paths.greeter && DrivesManager.count > 0,
      status: () => I18n.tr("{0} plugged in", DrivesManager.count),
      options: () => DrivesManager.drives.map(drive => ({
              title: DriveInfo.displayName(drive, I18n.tr("Drive")),
              subtitle: DrivesManager.statusText(drive),
              glyph: DriveInfo.icon(drive),
              value: drive.id
            })),
      run: (arg, value) => {
        const wanted = String(arg ?? "").trim().toLowerCase();
        const drive = value ? DrivesManager.driveById(value) : wanted !== "" ? DrivesManager.drives.find(d => DrivesManager.nameOf(d).toLowerCase().startsWith(wanted)) ?? null : DrivesManager.count === 1 ? DrivesManager.drives[0] : null;
        if (drive)
          DrivesManager.eject(drive);
        return false;
      }
    },
    // --- Notifications & idle ---
    Object.assign(root._switch("dnd", "toggleDnd", ["quiet"], "Turn do not disturb on or off"), {
      glyph: "notifications_off"
    }), Object.assign(root._action("clear", "clearNotifications", ["clear-notifications"], "Clear all notifications"), {
      confirm: true,
      status: () => NotificationManager.count > 0 ? I18n.tr("{0} notifications", NotificationManager.count) : ""
    }),
    {
      name: "caffeine",
      aliases: ["awake", "inhibit"],
      glyph: "coffee",
      usage: "[on | off | 30m]",
      description: () => I18n.tr("Keep the screen awake"),
      status: () => IdleManager.caffeineTimed ? IdleManager.caffeineTextNow() : IdleManager.caffeine ? I18n.tr("On") : I18n.tr("Off"),
      options: () => root._onOffOptions(),
      run: (arg, value) => {
        // A duration: on for that long
        if (IdleManager.startCaffeineText(value ?? arg))
          return false;
        ActionsManager.run("idleInhibit", {
          "call": root._call(value ?? arg)
        });
        return false;
      }
    },
    root._switch("nightlight", "nightLight", ["night", "sunset"], "Warmer screen colors"), root._switch("powersaver", "powerSaver", ["eco", "power-saver"], "Turn the power saver profile on or off"),
    {
      name: "dev",
      aliases: ["devmode"],
      glyph: "code",
      usage: "[on | off | rebuild | set <path>]",
      description: () => I18n.tr("Dev mode: rebuild the schema and axiom as you edit them"),
      available: () => BackendManager.ready,
      status: () => DevManager.building ? I18n.tr("Building…") : DevManager.enabled ? I18n.tr("On") : I18n.tr("Off"),
      // `set <path>` is typed out, never offered: no options past "set"
      options: arg => /^\s*set(\s|$)/.test(arg ?? "") ? [] : root._onOffOptions().concat(DevManager.available ? [
          {
            title: "rebuild",
            value: "rebuild"
          }
        ] : []),
      run: (arg, value) => {
        // `set <path>` makes that clone the dev tree; without a path, back
        // to typing one
        const set = value === undefined ? (arg ?? "").match(/^\s*set(?:\s+(.*))?$/) : null;
        if (set) {
          const path = (set[1] ?? "").trim();
          if (path === "")
            return "/dev set ";
          DevManager.setTree(path);
          return false;
        }
        if (((value ?? arg) ?? "").trim() === "rebuild") {
          DevManager.rebuild();
          return false;
        }
        const on = root._onOff(value ?? arg);
        DevManager.setEnabled(on === null ? !DevManager.enabled : on);
        return false;
      }
    },
    // --- Workspaces & shell ---
    {
      name: "ws",
      aliases: ["workspace"],
      glyph: "numbers",
      usage: "<number>",
      needsArg: true,
      description: () => I18n.tr("Go to a workspace"),
      run: arg => {
        const id = parseInt(arg.trim());
        if (id > 0)
          CompositorManager.goToWorkspace(id);
        else
          return false;
      }
    },
    {
      name: "config",
      aliases: ["set", "cfg"],
      glyph: "settings",
      usage: "<setting> <value> | save <name> | restore <name> | example <name> | community <search>",
      needsArg: true,
      description: () => I18n.tr("Change a setting, save and restore the config, or apply an example or community setup"),
      options: arg => root._config.options(arg),
      run: (arg, value) => root._config.run(value)
    },
    {
      name: "chat",
      aliases: ["ai"],
      glyph: "smart_toy",
      usage: "[conversation]",
      description: () => I18n.tr("Open the chat, a new conversation or a saved one (@ asks a question)"),
      status: () => ChatManager.busy ? I18n.tr("Replying…") : ChatManager.conversation.title,
      options: () => [
          {
            title: I18n.tr("New conversation"),
            subtitle: ChatConfig.defaultPreset,
            glyph: "edit_square",
            value: ""
          }
        ].concat(ChatManager.conversations.map(c => ({
              title: c.title || I18n.tr("Untitled"),
              subtitle: I18n.formatDate(new Date(c.updated), I18n.dateFormat("mediumDate")),
              glyph: "chat",
              value: c.id
            }))),
      run: (arg, value) => {
        // After the launcher has closed, so the overlay gets the keyboard
        Qt.callLater(() => {
          if (value === "")
            ChatManager.newConversation(ChatConfig.defaultPreset);
          else if (value !== undefined)
            ChatManager.open(value);
          ChatManager.openPage();
        });
      }
    },
    {
      name: "notes",
      aliases: ["note"],
      glyph: "sticky_note_2",
      usage: "[text]",
      description: () => I18n.tr("Search the notes, by name and text"),
      options: arg => root._notes(arg),
      run: (arg, value) => {
        // After the launcher has closed, so the overlay gets the keyboard
        Qt.callLater(() => NotesManager.openNotes(value?.path, value?.line));
      }
    },
    {
      name: "calendar",
      aliases: ["cal", "agenda"],
      glyph: "calendar_month",
      description: () => I18n.tr("Open the calendar"),
      available: () => !Paths.greeter,
      // After the launcher has closed, so the overlay gets the keyboard
      run: () => Qt.callLater(() => CalendarManager.openPage())
    },
    {
      name: "todo",
      aliases: ["task", "todos"],
      glyph: "checklist",
      usage: "[text]",
      description: () => I18n.tr("Add a todo, or tick one off"),
      available: () => !Paths.greeter,
      status: () => TodoManager.openCount > 0 ? I18n.tr("{0} to do", TodoManager.openCount) : "",
      options: arg => root._todo(arg),
      // Ticking one off keeps the launcher open for the next
      run: (arg, value) => {
        if (value?.uid) {
          TodoManager.toggle(value.uid);
          return false;
        }
        return TodoManager.add(value?.add ?? arg) === "" ? false : undefined;
      }
    },
    {
      name: "pomodoro",
      aliases: ["focus"],
      glyph: "timer",
      usage: "[start | pause | skip | stop]",
      description: () => I18n.tr("Start or pause the pomodoro timer"),
      available: () => !Paths.greeter,
      status: () => PomodoroManager.idle ? "" : PomodoroManager.phaseLabel + " · " + PomodoroManager.remainingTextNow(),
      options: () => ["start", "pause", "skip", "stop"].map(word => ({
              title: word,
              value: word
            })),
      run: (arg, value) => {
        const word = (value ?? arg ?? "").trim().toLowerCase();
        if (word === "start")
          PomodoroManager.start();
        else if (word === "pause")
          PomodoroManager.pause();
        else if (word === "skip")
          PomodoroManager.skip();
        else if (word === "stop")
          PomodoroManager.stop();
        else
          PomodoroManager.toggle();
        return false;
      }
    },
    {
      name: "timer",
      aliases: ["countdown"],
      glyph: "hourglass_top",
      usage: "<10m | 1h30m | 1:30> [label] | pause | reset",
      description: () => I18n.tr("Set a one-off timer"),
      available: () => !Paths.greeter,
      status: () => StopwatchManager.timerIdle ? "" : StopwatchManager.timerTextNow(),
      options: arg => root._timer(arg),
      run: (arg, value) => {
        const word = (value?.word ?? arg ?? "").trim().toLowerCase();
        // Pause and resume only a set timer (toggling an idle one would
        // start its last duration again)
        if (word === "pause" || word === "resume") {
          if (!StopwatchManager.timerIdle)
            StopwatchManager.toggleTimer();
        } else if (word === "reset")
          StopwatchManager.resetTimer();
        else
          return StopwatchManager.startTimerText(value?.text ?? arg) ? undefined : false;
        return false;
      }
    },
    {
      name: "stopwatch",
      aliases: ["sw"],
      glyph: "timer",
      usage: "[start | pause | lap | reset]",
      description: () => I18n.tr("Start, pause or lap the stopwatch"),
      available: () => !Paths.greeter,
      status: () => StopwatchManager.stopwatchIdle ? "" : StopwatchManager.elapsedTextNow(),
      options: () => ["start", "pause", "lap", "reset"].map(word => ({
              title: word,
              value: word
            })),
      run: (arg, value) => {
        const word = (value ?? arg ?? "").trim().toLowerCase();
        if (word === "lap")
          StopwatchManager.lap();
        else if (word === "reset")
          StopwatchManager.resetStopwatch();
        else if (word === "" || (word === "start" && !StopwatchManager.stopwatchRunning) || (word === "pause" && StopwatchManager.stopwatchRunning))
          StopwatchManager.toggleStopwatch();
        return false;
      }
    },
    {
      name: "event",
      aliases: ["newevent", "addevent"],
      glyph: "event",
      usage: "<when> <title>",
      needsArg: true,
      description: () => I18n.tr("Add an event, e.g. tomorrow 3pm Dentist"),
      available: () => !Paths.greeter && CalendarManager.writableCalendars.length > 0,
      options: arg => root._event(arg),
      run: arg => CalendarManager.quickAdd(arg) ? undefined : false
    },
    {
      name: "update",
      aliases: ["upgrade"],
      glyph: "update",
      // A package (or any tree with no .git) updates with the system
      available: () => !Paths.packaged && !SelfUpdateManager.managed,
      // Installing asks first; a check doesn't
      get confirm() {
        return SelfUpdateManager.available;
      },
      description: () => SelfUpdateManager.available ? I18n.tr("Update axiom to {0}", SelfUpdateManager.latest) : I18n.tr("Check for axiom updates"),
      status: () => SelfUpdateManager.busy ? I18n.tr("Checking…") : SelfUpdateManager.available ? I18n.tr("{0} available", SelfUpdateManager.latest) : (SelfUpdateManager.current || SelfUpdateManager.commit),
      run: () => {
        // Otherwise check, on the page that shows the result
        if (SelfUpdateManager.available) {
          SelfUpdateManager.apply();
        } else {
          SelfUpdateManager.check();
          SelfUpdateManager.openSettings();
        }
      }
    },
    {
      name: "welcome",
      aliases: ["setup", "onboarding"],
      glyph: "waving_hand",
      description: () => I18n.tr("Run the first-time setup again"),
      run: () => {
        OnboardingManager.open();
      }
    },
    {
      name: "screenshot",
      aliases: ["shot", "capture"],
      glyph: "screenshot_region",
      usage: "[region | window | screen]",
      description: () => I18n.tr("Take a screenshot"),
      // I18n.tr("region") I18n.tr("window") I18n.tr("screen")
      options: () => ScreenshotManager.kinds.map(kind => ({
              title: kind,
              subtitle: I18n.tr(kind),
              value: kind
            })),
      run: (arg, value) => {
        ScreenshotManager.take(value ?? (arg || "region"));
      }
    },
    Object.assign(root._action("record", "screenRecord", ["recording", "screencast"], ""), {
      glyph: "videocam",
      description: () => ScreenshotManager.recording ? I18n.tr("Stop recording the screen") : I18n.tr("Record the screen"),
      available: () => ScreenshotManager.hasRecorder || ScreenshotManager.recording,
      status: undefined,
      run: () => {
        ActionsManager.run("screenRecord");
      }
    }),
    {
      name: "reload",
      aliases: [],
      glyph: "refresh",
      description: () => I18n.tr("Reload the shell"),
      run: () => LockManager.reload()
    },
    // --- Other searches ---
    root._prefix("calc", ["math"], "calculate", "Calculate (or start with =)", "=", () => LauncherConfig.calculator), root._prefix("run", ["exec", "sh"], "terminal", "Run a shell command (or start with >)", ">", () => LauncherConfig.runCommands), root._prefix("web", ["search"], "web", "Search the web (or start with ?)", "?", () => LauncherConfig.webSearch), root._prefix("clipboard", ["clip", "paste"], "content_paste", "Search the clipboard history (or start with :)", ":", () => LauncherConfig.clipboard), root._prefix("emoji", ["emojis", "emoticon"], "mood", "Search emoji (or start with ;)", ";", () => LauncherConfig.emoji), root._prefix("files", ["find"], "folder_open", "Search your files (or start with ~)", "~", () => LauncherConfig.files), root._prefix("help", ["commands"], "help", "List every command", "/", () => true)]

  // --- Builders for families of alike commands ---

  // Runs one of the shell's actions (ActionsManager: the keybind table's,
  // as its key would) with `call` ("toggle" when missing); its glyph is the
  // action's, its status the action's state, and it asks for a second
  // Enter where a tile asks for a second click (log out, restart, shut
  // down)
  function _action(name, id, aliases, description, call) {
    return {
      name: name,
      aliases: aliases,
      glyph: SessionManager.sessionActionInfo(id)?.icon ?? KeybindManager.actionIcon(id),
      confirm: ActionsManager.destructive(id),
      // I18n.tr("Lock the screen") I18n.tr("Suspend to RAM") I18n.tr("Hibernate to disk")
      // I18n.tr("End the session") I18n.tr("Restart the computer") I18n.tr("Turn the computer off")
      // I18n.tr("Open the power menu") I18n.tr("Open or close the workspace overview")
      // I18n.tr("Use the theme's dark variant") I18n.tr("Use the theme's light variant")
      // I18n.tr("Toggle light and dark") I18n.tr("Next wallpaper of the rotation")
      // I18n.tr("Mute or unmute the output") I18n.tr("Mute or unmute the microphone")
      // I18n.tr("Clear all notifications")
      description: () => I18n.tr(description),
      available: () => ActionsManager.available(id),
      status: () => ActionsManager.info(id).status,
      run: () => {
        ActionsManager.run(id, {
          "call": call ?? "toggle"
        });
        return false;
      }
    };
  }

  // An action switched on or off ("/wifi on", "/wifi off"), else toggled
  function _switch(name, id, aliases, description) {
    return Object.assign(root._action(name, id, aliases, description), {
      usage: "[on | off]",
      // I18n.tr("Turn wifi on or off") I18n.tr("Turn bluetooth on or off")
      // I18n.tr("Turn airplane mode on or off") I18n.tr("Turn do not disturb on or off")
      // I18n.tr("Warmer screen colors") I18n.tr("Turn the power saver profile on or off")
      description: () => I18n.tr(description),
      options: () => root._onOffOptions(),
      run: (arg, value) => {
        ActionsManager.run(id, {
          "call": root._call(value ?? arg)
        });
        return false;
      }
    });
  }

  // Opens the overlay on a page by view type
  // `before` (optional) runs first, e.g. to pick what the page shows
  function _page(name, aliases, type, description, before) {
    return {
      name: name,
      aliases: aliases,
      glyph: OverlayConfig.viewIcon(type),
      // I18n.tr("Open the settings") I18n.tr("Open the themes page") I18n.tr("Open the bar editor")
      // I18n.tr("Show the keybinds") I18n.tr("Edit the overlay pages and menus")
      // I18n.tr("Edit the menus") I18n.tr("Arrange and set up monitors")
      // I18n.tr("Make widgets from scripts") I18n.tr("Edit the window rules") I18n.tr("Make a rule for the focused window")
      description: () => I18n.tr(description),
      // Not where the compositor can't do what the page needs (`x-needs`)
      available: () => {
        const needs = OverlayConfig.viewInfo(type)?.needs ?? "";
        return needs === "" || CompositorManager.supports[needs] === true;
      },
      run: () => {
        if (before)
          before();
        ShellManager.openOverlayPage(type);
      }
    };
  }

  // Picks the default audio device from `nodes()`
  function _device(name, aliases, glyph, description, nodes, current) {
    return {
      name: name,
      aliases: aliases,
      glyph: glyph,
      usage: "<device>",
      needsArg: true,
      // I18n.tr("Choose the audio output") I18n.tr("Choose the audio input")
      description: () => I18n.tr(description),
      status: () => current()?.description ?? "",
      options: () => nodes().map(node => ({
              title: node.description || node.name,
              subtitle: node === current() ? I18n.tr("Current") : "",
              value: node
            })),
      run: (arg, value) => {
        if (value)
          AudioManager.setDefault(value);
        return false;
      }
    };
  }

  function _media(name, aliases, description, id) {
    return Object.assign(root._action(name, id, aliases, description), {
      // I18n.tr("Play or pause") I18n.tr("Next track") I18n.tr("Previous track")
      description: () => I18n.tr(description),
      available: () => MediaManager.hasActivePlayer,
      status: () => [MediaManager.trackTitle, MediaManager.trackArtist].filter(s => s).join(" · ")
    });
  }

  // Switches the search to one of the prefixes
  function _prefix(name, aliases, glyph, description, prefix, available) {
    return {
      name: name,
      aliases: aliases,
      glyph: glyph,
      // I18n.tr("Calculate (or start with =)") I18n.tr("Run a shell command (or start with >)")
      // I18n.tr("Search the web (or start with ?)") I18n.tr("List every command")
      // I18n.tr("Search the clipboard history (or start with :)") I18n.tr("Search emoji (or start with ;)")
      // I18n.tr("Search your files (or start with ~)")
      description: () => I18n.tr(description),
      available: available,
      run: arg => prefix + arg
    };
  }

  // --- Option lists ---

  function _onOffOptions() {
    return [
      {
        title: "on",
        value: "on"
      },
      {
        title: "off",
        value: "off"
      }
    ];
  }

  // An action's call for "on" / "off" (open / close), else "toggle"
  function _call(arg) {
    const on = root._onOff(arg);
    return on === null ? "toggle" : on ? "open" : "close";
  }

  // "on" → true, "off" → false, anything else (a toggle) → null
  function _onOff(arg) {
    const word = (arg ?? "").trim().toLowerCase();
    if (["on", "1", "true", "yes"].includes(word))
      return true;
    if (["off", "0", "false", "no"].includes(word))
      return false;
    return null;
  }

  // Every note with no text, else NotesManager.search's results (asked for
  // here, the rows re-read when it answers; name matches meanwhile)
  function _notes(arg) {
    const q = arg.trim();
    const row = result => ({
          title: result.title,
          subtitle: result.line < 0 ? result.path : I18n.tr("line {0}", result.line + 1) + " · " + result.snippet,
          glyph: result.line < 0 ? "description" : "notes",
          matched: true,
          value: result
        });
    if (q === "")
      return NotesManager.allNotes.map(path => row({
          path: path,
          title: NotesManager.titleOf(path),
          line: -1
        }));
    if (NotesManager.lastSearch.query === q)
      return NotesManager.lastSearch.results.map(row);
    NotesManager.search(q, () => LauncherManager.query(LauncherManager.text));
    return NotesManager.allNotes.filter(path => path.toLowerCase().includes(q.toLowerCase())).map(path => row({
        path: path,
        title: NotesManager.titleOf(path),
        line: -1
      }));
  }

  // With text, a row adding it; then the open todos matching it, each
  // ticked off when picked
  function _todo(arg) {
    const q = arg.trim();
    const add = q === "" ? [] : [
      {
        title: I18n.tr("Add \"{0}\"", q),
        subtitle: I18n.tr("To the todo list"),
        glyph: "add_task",
        matched: true,
        value: {
          add: q
        }
      }
    ];
    const open = TodoManager.shownItems.filter(item => !item.done && (q === "" || item.summary.toLowerCase().includes(q.toLowerCase())));
    return add.concat(open.map(item => ({
          title: item.summary,
          subtitle: I18n.tr("Tick off"),
          glyph: "check_box_outline_blank",
          matched: true,
          value: item
        })));
  }

  // A row starting the typed timer (or saying what to type), then pause and
  // reset while one is set
  function _timer(arg) {
    const parsed = StopwatchClock.parse(arg, Date.now());
    const rows = [];
    if (parsed.ms > 0)
      rows.push({
        title: I18n.tr("Start a {0} timer", StopwatchClock.format(parsed.ms, false, true)),
        subtitle: parsed.label,
        glyph: "hourglass_top",
        matched: true,
        value: {
          text: arg
        }
      });
    else if (arg.trim() === "")
      rows.push({
        title: I18n.tr("How long"),
        subtitle: I18n.tr("10m, 1h30m, 90s, 1:30 or at 17:30, then a label if you like"),
        glyph: "hourglass_top",
        matched: true,
        value: {
          text: ""
        }
      });
    if (!StopwatchManager.timerIdle)
      rows.push({
        title: StopwatchManager.timerRunning ? "pause" : "resume",
        glyph: StopwatchManager.timerRunning ? "pause" : "play_arrow",
        value: {
          word: StopwatchManager.timerRunning ? "pause" : "resume"
        }
      }, {
        title: "reset",
        glyph: "stop",
        value: {
          word: "reset"
        }
      });
    return rows;
  }

  // The event /event would add, as a row to check before Enter
  function _event(arg) {
    const parsed = CalendarManager.parseQuickAdd(arg);
    if (!parsed)
      return [
        {
          title: I18n.tr("When, then what"),
          subtitle: I18n.tr("today, tomorrow, a weekday or a date; a time or a range (9-10:30); all day"),
          glyph: "event",
          matched: true,
          value: null
        }
      ];
    const day = I18n.formatDate(new Date(parsed.start), I18n.dateFormat("longDate"));
    const time = I18n.tr("{0} – {1}", I18n.formatDate(new Date(parsed.start), CalendarConfig.timeFormat), I18n.formatDate(new Date(parsed.end), CalendarConfig.timeFormat));
    const calendar = CalendarManager.calendar(CalendarManager.newEventCalendar);
    return [
      {
        title: parsed.title,
        subtitle: [day, parsed.allDay ? I18n.tr("All day") : time, calendar?.name ?? ""].filter(part => part).join(" · "),
        glyph: "event",
        matched: true,
        value: parsed
      }
    ];
  }

  function _overlayPages() {
    const pages = OverlayConfig.views.map(view => {
      const info = OverlayConfig.viewInfo(view.type);
      return {
        title: view.name || info?.label || view.type,
        subtitle: view.name ? info?.label ?? view.type : "",
        glyph: info?.icon,
        value: view.name || view.type
      };
    });
    return pages.concat([
      {
        title: I18n.tr("Layouts"),
        glyph: OverlayConfig.viewIcon("Layouts"),
        value: "Layouts"
      }
    ]);
  }

  // Every wallpaper transition, by its settings label (its name,
  // capitalized: the names match the labels)
  function _transitions() {
    // I18n.tr("Fade") I18n.tr("Wipe") I18n.tr("Slide") I18n.tr("Grow")
    // I18n.tr("Shrink") I18n.tr("Wave") I18n.tr("Dissolve")
    // I18n.tr("Pixelate") I18n.tr("Blinds") I18n.tr("Tiles") I18n.tr("Zoom")
    // I18n.tr("Ripple") I18n.tr("Swirl") I18n.tr("Blur") I18n.tr("Clock")
    return WallpaperTransitions.names.map(name => ({
          title: I18n.tr(name.charAt(0).toUpperCase() + name.slice(1)),
          glyph: "animation",
          value: name
        }));
  }

  function _wallpapers() {
    const rows = [
      {
        title: I18n.tr("Random"),
        glyph: "shuffle",
        value: "random"
      }
    ];
    for (const url of WallpaperManager.images)
      rows.push({
        title: decodeURIComponent(url.split("/").pop().replace(/\.[^.]*$/, "")),
        image: url,
        value: url
      });
    return rows;
  }
}
