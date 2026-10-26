pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

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
 *     confirm,    asks for a second Enter first (destructive session actions)
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

  readonly property var list: [
    // --- Session ---
    root._session("lock", ["lock-screen"], "Lock the screen"), root._session("suspend", ["sleep"], "Suspend to RAM"), root._session("hibernate", [], "Hibernate to disk"), root._session("logout", ["exit"], "End the session"), root._session("reboot", ["restart"], "Restart the computer"), root._session("poweroff", ["shutdown"], "Turn the computer off"),
    // --- Surfaces ---
    {
      name: "power",
      aliases: ["powermenu"],
      glyph: "power_settings_new",
      description: () => I18n.tr("Open the power menu"),
      run: () => ShellManager.openPowerMenu()
    },
    {
      name: "workspaces",
      aliases: ["overview"],
      glyph: "grid_view",
      description: () => I18n.tr("Open the workspace overview"),
      run: () => ShellManager.toggleWorkspaceOverlay()
    },
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
    root._page("settings", ["prefs", "options"], "Settings", "Open the settings"), root._page("themes", [], "Themes", "Open the themes page"), root._page("bar", ["bareditor"], "BarEditor", "Open the bar editor"), root._page("keybinds", ["keys", "shortcuts"], "Keybinds", "Show the keybinds"), root._page("layouts", ["editor", "overlay-editor"], "Layouts", "Edit the overlay pages and edge menus", () => OverlayManager.editPages()), root._page("menus", ["edge-menus", "menu-editor"], "Layouts", "Edit the edge menus", () => OverlayManager.editMenus()), root._page("monitors", ["displays", "screens"], "Monitors", "Arrange and set up monitors"),
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
    {
      name: "dark",
      aliases: [],
      glyph: "clear_night",
      description: () => I18n.tr("Use the theme's dark variant"),
      run: () => {
        ThemeManager.setLightMode(false);
        return false;
      }
    },
    {
      name: "light",
      aliases: [],
      glyph: "sunny",
      description: () => I18n.tr("Use the theme's light variant"),
      run: () => {
        ThemeManager.setLightMode(true);
        return false;
      }
    },
    {
      name: "mode",
      aliases: ["darkmode"],
      glyph: "contrast",
      description: () => I18n.tr("Toggle light and dark"),
      status: () => Appearance.darkMode ? I18n.tr("Dark") : I18n.tr("Light"),
      run: () => {
        ThemeManager.toggleDarkMode();
        return false;
      }
    },
    {
      name: "wallpaper",
      aliases: ["wall", "bg"],
      glyph: "image",
      usage: "<file>",
      needsArg: true,
      description: () => I18n.tr("Set the focused monitor's wallpaper"),
      options: () => root._wallpapers(),
      run: (arg, value) => {
        let url = value;
        if (url === "random") {
          const walls = root._wallpapers().slice(1);
          url = walls.length > 0 ? walls[Math.floor(Math.random() * walls.length)].value : "";
        }
        if (url)
          WallpaperManager.pick(url, "", "");
        return false;
      }
    },
    {
      name: "nextwallpaper",
      aliases: ["nextwall", "rotate"],
      glyph: "shuffle",
      description: () => I18n.tr("Next wallpaper of the rotation"),
      run: () => {
        WallpaperManager.next();
        return false;
      }
    },
    {
      name: "generate",
      aliases: ["pywal"],
      glyph: "auto_fix",
      description: () => I18n.tr("Generate themes from the current wallpaper"),
      status: () => ThemeManager.isGenerating ? I18n.tr("Generating…") : "",
      run: () => {
        const monitor = ShellManager.targetFor(LauncherConfig.monitors);
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
    {
      name: "mute",
      aliases: [],
      glyph: "volume_off",
      description: () => I18n.tr("Mute or unmute the output"),
      status: () => AudioManager.muted ? I18n.tr("Muted") : "",
      run: () => {
        AudioManager.toggleMute();
        return false;
      }
    },
    {
      name: "mic",
      aliases: ["microphone"],
      glyph: "mic",
      description: () => I18n.tr("Mute or unmute the microphone"),
      status: () => AudioManager.sourceMuted ? I18n.tr("Muted") : "",
      run: () => {
        AudioManager.toggleSourceMute();
        return false;
      }
    },
    root._device("output", ["sink", "speakers"], "speaker", "Choose the audio output", () => AudioManager.sinks, () => AudioManager.defaultSink), root._device("input", ["source"], "mic", "Choose the audio input", () => AudioManager.sources, () => AudioManager.defaultSource), root._media("play", ["pause"], "play_pause", "Play or pause", () => MediaManager.togglePlayPause()), root._media("next", ["skip"], "skip_next", "Next track", () => MediaManager.next()), root._media("prev", ["previous", "back"], "skip_previous", "Previous track", () => MediaManager.previous()),
    // --- Connectivity ---
    {
      name: "wifi",
      aliases: ["wlan"],
      glyph: "wifi",
      usage: "[on | off]",
      description: () => I18n.tr("Turn wifi on or off"),
      available: () => NetworkingManager.available,
      status: () => NetworkingManager.wifiEnabled ? I18n.tr("On") : I18n.tr("Off"),
      options: () => root._onOffOptions(),
      run: (arg, value) => {
        const on = root._onOff(value ?? arg);
        NetworkingManager.setWifiEnabled(on === null ? !NetworkingManager.wifiEnabled : on);
        return false;
      }
    },
    {
      name: "bluetooth",
      aliases: ["bt"],
      glyph: "bluetooth",
      usage: "[on | off]",
      description: () => I18n.tr("Turn bluetooth on or off"),
      available: () => BluetoothManager.available,
      status: () => BluetoothManager.enabled ? I18n.tr("On") : I18n.tr("Off"),
      options: () => root._onOffOptions(),
      run: (arg, value) => {
        const on = root._onOff(value ?? arg);
        BluetoothManager.setEnabled(on === null ? !BluetoothManager.enabled : on);
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
    // --- Notifications & idle ---
    {
      name: "dnd",
      aliases: ["quiet"],
      glyph: "notifications_off",
      usage: "[on | off]",
      description: () => I18n.tr("Do not disturb"),
      status: () => NotificationManager.dnd ? I18n.tr("On") : I18n.tr("Off"),
      options: () => root._onOffOptions(),
      run: (arg, value) => {
        const on = root._onOff(value ?? arg);
        NotificationManager.setDnd(on === null ? !NotificationManager.dnd : on);
        return false;
      }
    },
    {
      name: "clear",
      aliases: ["clear-notifications"],
      glyph: "clear_all",
      description: () => I18n.tr("Clear all notifications"),
      status: () => NotificationManager.count > 0 ? I18n.tr("{0} notifications", NotificationManager.count) : "",
      run: () => {
        NotificationManager.clearAll();
        return false;
      }
    },
    {
      name: "caffeine",
      aliases: ["awake", "inhibit"],
      glyph: "coffee",
      usage: "[on | off]",
      description: () => I18n.tr("Keep the screen awake"),
      status: () => IdleManager.caffeine ? I18n.tr("On") : I18n.tr("Off"),
      options: () => root._onOffOptions(),
      run: (arg, value) => {
        const on = root._onOff(value ?? arg);
        IdleManager.caffeine = on === null ? !IdleManager.caffeine : on;
        return false;
      }
    },
    {
      name: "nightlight",
      aliases: ["night", "sunset"],
      glyph: "nightlight",
      usage: "[on | off]",
      description: () => I18n.tr("Warmer screen colors"),
      available: () => NightLightManager.available,
      status: () => NightLightManager.active ? I18n.tr("On") : I18n.tr("Off"),
      options: () => root._onOffOptions(),
      run: (arg, value) => {
        const on = root._onOff(value ?? arg);
        NightLightManager.setActive(on === null ? !NightLightManager.active : on);
        return false;
      }
    },
    {
      name: "dev",
      aliases: ["devmode"],
      glyph: "code",
      usage: "[on | off | rebuild]",
      description: () => I18n.tr("Dev mode: rebuild the schema and axiom as you edit them"),
      available: () => BackendManager.ready,
      status: () => DevManager.building ? I18n.tr("Building…") : DevManager.enabled ? I18n.tr("On") : I18n.tr("Off"),
      options: () => root._onOffOptions().concat(DevManager.enabled && DevManager.available ? [
          {
            title: "rebuild",
            value: "rebuild"
          }
        ] : []),
      run: (arg, value) => {
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
      options: arg => root._configOptions(arg),
      run: (arg, value) => root._configRun(value)
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
        // After the launcher has closed, so the overlay gets the keyboard.
        // An overlay page with a Notes module, else an edge menu with one
        Qt.callLater(() => {
          const page = OverlayConfig.pageWithModule("Notes");
          const menu = page === "" ? EdgeMenusConfig.menuWithModule("Notes") : null;
          if (page === "" && !menu) {
            NotificationManager.sendNotification("axiom", I18n.tr("No notes module"), I18n.tr("Add a Notes module to an overlay page or an edge menu."));
            return;
          }
          if (value)
            NotesManager.requestOpen(value.path, value.line, menu ? "edgeMenu:" + menu.id : "overlay");
          if (menu)
            EdgeMenuManager.reveal(menu.id);
          else
            ShellManager.openOverlayPage(page);
        });
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
      // A package updates with the system
      available: () => !Paths.packaged,
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
      usage: "<region|window|screen>",
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
    {
      name: "record",
      aliases: ["recording", "screencast"],
      glyph: "videocam",
      description: () => ScreenshotManager.recording ? I18n.tr("Stop recording the screen") : I18n.tr("Record the screen"),
      available: () => ScreenshotManager.hasRecorder || ScreenshotManager.recording,
      run: () => {
        ScreenshotManager.toggleRecording();
      }
    },
    {
      name: "reload",
      aliases: [],
      glyph: "refresh",
      description: () => I18n.tr("Reload the shell"),
      run: () => Quickshell.reload(false)
    },
    // --- Other searches ---
    root._prefix("calc", ["math"], "calculate", "Calculate (or start with =)", "=", () => LauncherConfig.calculator), root._prefix("run", ["exec", "sh"], "terminal", "Run a shell command (or start with >)", ">", () => LauncherConfig.runCommands), root._prefix("web", ["search"], "web", "Search the web (or start with ?)", "?", () => LauncherConfig.webSearch), root._prefix("clipboard", ["clip", "paste"], "content_paste", "Search the clipboard history (or start with :)", ":", () => LauncherConfig.clipboard), root._prefix("emoji", ["emojis", "emoticon"], "mood", "Search emoji (or start with ;)", ";", () => LauncherConfig.emoji), root._prefix("help", ["commands"], "help", "List every command", "/", () => true)]

  // --- Builders for families of alike commands ---

  function _session(action, aliases, description) {
    return {
      name: action,
      aliases: aliases,
      glyph: ShellManager.sessionActionInfo(action).icon,
      confirm: ShellManager.destructiveActions.includes(action),
      // I18n.tr("Lock the screen") I18n.tr("Suspend to RAM") I18n.tr("Hibernate to disk")
      // I18n.tr("End the session") I18n.tr("Restart the computer") I18n.tr("Turn the computer off")
      description: () => I18n.tr(description),
      run: () => ShellManager.sessionAction(action)
    };
  }

  // Opens the overlay on a page by view type
  // `before` (optional) runs first, e.g. to pick what the page shows
  function _page(name, aliases, type, description, before) {
    return {
      name: name,
      aliases: aliases,
      glyph: OverlayConfig.viewIcon(type),
      // I18n.tr("Open the settings") I18n.tr("Open the themes page") I18n.tr("Open the bar editor")
      // I18n.tr("Show the keybinds") I18n.tr("Edit the overlay pages and edge menus")
      // I18n.tr("Edit the edge menus") I18n.tr("Arrange and set up monitors")
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

  function _media(name, aliases, glyph, description, action) {
    return {
      name: name,
      aliases: aliases,
      glyph: glyph,
      // I18n.tr("Play or pause") I18n.tr("Next track") I18n.tr("Previous track")
      description: () => I18n.tr(description),
      available: () => MediaManager.hasActivePlayer,
      status: () => [MediaManager.trackTitle, MediaManager.trackArtist].filter(s => s).join(" · "),
      run: () => {
        action();
        return false;
      }
    };
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
      description: () => I18n.tr(description),
      available: available,
      run: arg => prefix + arg
    };
  }

  // --- /config ---

  // Every row's title is the whole argument it stands for, since rows are
  // matched against the typed argument and Tab completes to the title
  function _configOptions(arg) {
    const space = arg.indexOf(" ");
    if (space < 0) {
      const rows = [
        {
          title: "save",
          subtitle: SavedConfigsManager.modified ? I18n.tr("Save changes to \"{0}\"", SavedConfigsManager.active) : I18n.tr("Save the current config under a name"),
          glyph: "save",
          value: {
            next: "save "
          }
        },
        {
          title: "restore",
          subtitle: I18n.tr("Restore a saved config"),
          glyph: "settings_backup_restore",
          value: {
            next: "restore "
          }
        },
        {
          title: "example",
          subtitle: I18n.tr("Apply an example setup (the current config is saved first)"),
          glyph: "auto_awesome_mosaic",
          value: {
            next: "example "
          }
        }
      ].concat(CommunitySetupsManager.enabled ? [
        {
          title: "community",
          subtitle: I18n.tr("Search the community setups and apply one (the current config is saved first)"),
          glyph: "groups",
          value: {
            next: "community "
          }
        }
      ] : []);
      return rows.concat(SettingsManager.settingPaths.map(entry => ({
            title: entry.key,
            subtitle: I18n.tr(entry.schema.title ?? entry.key) + " · " + root._configShow(SettingsManager.valueOf(entry.key), entry.schema),
            value: {
              next: entry.key + " "
            }
          })));
    }

    const head = arg.slice(0, space);
    const rest = arg.slice(space + 1);
    const names = root._savedConfigNames();
    // Only the active saved config is offered to overwrite; another is
    // replaced only when its name is typed in full, as on the settings page
    const active = SavedConfigsManager.active;
    if (head === "save") {
      const name = SavedConfigsManager.sanitize(rest);
      const rows = name === "" || name === active ? [] : [
        {
          title: "save " + rest.trim(),
          subtitle: names.includes(name) ? I18n.tr("Replace \"{0}\"", name) : I18n.tr("Save as \"{0}\"", name),
          value: {
            save: name
          }
        }
      ];
      return active === "" ? rows : rows.concat([
        {
          title: "save " + active,
          subtitle: SavedConfigsManager.modified ? I18n.tr("Save changes to the current config") : I18n.tr("No changes since saved"),
          value: {
            save: active
          }
        }
      ]);
    }
    if (head === "restore")
      return names.filter(saved => saved === active).concat(names.filter(saved => saved !== active)).map(saved => ({
            title: "restore " + saved,
            subtitle: saved !== active ? "" : SavedConfigsManager.modified ? I18n.tr("Current · discards unsaved changes") : I18n.tr("Current"),
            value: {
              restore: saved
            }
          }));

    if (head === "example")
      return SavedConfigsManager.examples.map(example => ({
            title: "example " + example.name,
            subtitle: example.description,
            value: {
              example: example.name
            }
          }));

    if (head === "community" && CommunitySetupsManager.enabled)
      return root._communityOptions(rest);

    const entry = SettingsManager.settingFor(head);
    if (!entry)
      return [
        {
          title: arg.trim(),
          subtitle: I18n.tr("No setting \"{0}\"", head),
          glyph: "warning",
          value: {}
        }
      ];
    const schema = entry.schema;
    const current = SettingsManager.valueOf(entry.key);
    const choices = schema.type === "boolean" ? ["on", "off"] : schema.type === "string" ? SettingsManager.optionsFor(schema) : null;
    const setRow = (text, parsed) => ({
          title: entry.key + " " + text,
          subtitle: parsed.error ?? (JSON.stringify(parsed.value) === JSON.stringify(current) ? I18n.tr("Current") : I18n.tr("Set {0} to {1} (now {2})", I18n.tr(schema.title ?? entry.key), root._configShow(parsed.value, schema), root._configShow(current, schema))),
          glyph: parsed.error ? "warning" : "",
          value: parsed.error ? {} : {
            key: entry.key,
            set: parsed.value
          }
        });
    // Last, so Enter still sets the first value; only while a card shows it
    const showRows = SettingsManager.locate(entry.key) ? [
      {
        title: I18n.tr("Show in settings"),
        subtitle: I18n.tr("Open the settings page on {0}", I18n.tr(schema.title ?? entry.key)),
        glyph: "settings",
        value: {
          show: entry.key
        }
      }
    ] : [];
    const typed = rest.trim();
    if (typed === "" && !choices)
      return [
        {
          title: entry.key,
          subtitle: I18n.tr("Type a value (now {0})", root._configShow(current, schema)),
          value: {
            next: entry.key + " "
          }
        }
      ].concat(showRows);
    let rows = [];
    // Typed text that isn't (the start of) a choice gets a row of its own,
    // so free values, and why one is rejected, show
    if (typed !== "" && !(choices ?? []).some(choice => choice.toLowerCase().startsWith(typed.toLowerCase())))
      rows.push(setRow(typed, SettingsManager.parseValue(schema, rest)));
    if (choices)
      rows = rows.concat(choices.map(choice => {
        const text = choice === "" ? "\"\"" : choice;
        return setRow(text, SettingsManager.parseValue(schema, text));
      }));
    return rows.concat(showRows);
  }

  function _configRun(value) {
    if (value?.next)
      return "/config " + value.next;
    if (value?.save) {
      SavedConfigsManager.save(value.save);
      return;
    }
    if (value?.restore) {
      SavedConfigsManager.restore(value.restore);
      return;
    }
    if (value?.example) {
      SavedConfigsManager.applyExample(value.example);
      return;
    }
    if (value?.community) {
      CommunitySetupsManager.apply(value.community, false);
      return;
    }
    // After the launcher has closed, so the overlay gets the keyboard
    if (value?.show) {
      Qt.callLater(() => SettingsManager.openSetting(value.show));
      return;
    }
    if (value?.key !== undefined && !SettingsManager.commitValue(value.key, value.set))
      console.warn("[LauncherCommands] Could not set", value.key);
    return false;
  }

  // The community setups matching `rest` (CommunityCatalog.search, so
  // `matched`), with their thumbnails; the catalog is downloaded the first
  // time they're asked for
  function _communityOptions(rest) {
    CommunitySetupsManager.open();
    if (!CommunitySetupsManager.loaded)
      return [
        {
          title: "community " + rest,
          subtitle: CommunitySetupsManager.loading ? I18n.tr("Loading the community setups…") : CommunitySetupsManager.status || I18n.tr("No community setups yet"),
          glyph: CommunitySetupsManager.loading ? "hourglass_empty" : "cloud_off",
          value: {}
        }
      ];
    return CommunitySetupsManager.search(rest, []).map(setup => ({
          title: "community " + setup.id,
          subtitle: setup.compatible ? I18n.tr("{0} by {1} · {2}", setup.title, setup.author, setup.description) : I18n.tr("{0} needs a newer axiom", setup.title),
          glyph: setup.compatible ? "" : "warning",
          image: CommunitySetupsManager.thumbs[setup.id] ?? "",
          matched: true,
          value: setup.compatible ? {
            community: setup.id
          } : {}
        }));
  }

  function _configShow(value, schema) {
    if (schema.type === "boolean")
      return value ? I18n.tr("On") : I18n.tr("Off");
    if (Array.isArray(value))
      return value.length > 0 ? value.join(", ") : I18n.tr("None");
    if (value === "")
      return I18n.tr("Empty");
    return String(value);
  }

  function _savedConfigNames() {
    const names = [];
    const model = SavedConfigsManager.model;
    for (let i = 0; i < model.count; i++)
      names.push(model.get(i, "fileBaseName"));
    return names;
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
    const parsed = StopwatchClock.parse(arg);
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
        subtitle: I18n.tr("10m, 1h30m, 90s or 1:30, then a label if you like"),
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

  function _wallpapers() {
    const rows = [
      {
        title: I18n.tr("Random"),
        glyph: "shuffle",
        value: "random"
      }
    ];
    const model = ThemeManager.wallpaperModel;
    for (let i = 0; i < model.count; i++)
      rows.push({
        title: model.get(i, "fileBaseName"),
        image: model.get(i, "fileUrl").toString(),
        value: model.get(i, "fileUrl").toString()
      });
    return rows;
  }
}
