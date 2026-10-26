//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QSG_RENDER_LOOP=threaded
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

pragma ComponentBehavior: Bound
import Quickshell
import qs.services.core
import qs.services.compositor
import qs.services.session
import qs.services.system
import qs.services.ui
import qs.services.apps
import qs.shell

// The shell's entrypoint: one top-level piece per surface (shell/), plus
// _services, which creates the services nothing else would reference. Run
// only by axiom (`axiom run`, which hands it the config): started any other
// way, or by an axiom built for other shell files, it shows only a notice
// saying how to start it (NoParentNotice).
ShellRoot {
  id: shellRoot

  // axiom started this shell with a config it can run on
  readonly property bool run: ConfigManager.available && BackendManager.incompatible === ""

  // Services with no UI of their own, which nothing else would create
  // (CompositorConfigManager only with configModes, where it has work at
  // start; elsewhere other services may still create it, and it stays
  // inert: live)
  readonly property var _services: run ? [DependencyManager, CompositorManager, CompositorManager.supports.configModes ? CompositorConfigManager : null, IdleManager, SelfUpdateManager, ChatManager, AudioManager, MediaManager, EdgeMenuManager, BrightnessManager, NotesManager, TodoManager, PomodoroManager, StopwatchManager, MonitorManager, OnboardingManager, ClipboardManager, NightLightManager, WallpaperManager, DockManager, SystemManager, BatteryManager, PolkitManager, GreeterManager, CalendarManager, CommunitySetupsManager] : []

  LazyLoader {
    active: !shellRoot.run

    NoParentNotice {}
  }

  LazyLoader {
    active: shellRoot.run

    Scope {
      Lockscreen {
        id: lockscreen
      }

      Notifications {
        id: notificationPopup
      }

      Overlay {
        id: overlay
      }

      Bar {
        id: mainBar
      }

      WorkspaceOverlay {
        id: workspaceOverlay
      }

      WindowSwitcher {
        id: windowSwitcher
      }

      Wallpaper {
        id: wallpaper
      }

      Desktop {
        id: desktop
      }

      Screenshot {
        id: screenshot
      }

      ScreenBorder {
        id: screenBorder
      }

      Backdrops {
        id: backdrops
      }

      BlurBacking {
        id: blurBacking
      }

      OSD {
        id: osd
      }

      AppLauncher {
        id: appLauncher
      }

      PowerMenu {
        id: powerMenu
      }

      EdgeMenus {
        id: edgeMenus
      }

      Dock {
        id: dock
      }

      MonitorPrompt {
        id: monitorPrompt
      }

      Onboarding {
        id: onboarding
      }

      IdleInhibit {
        id: idleInhibit
      }

      PolkitPrompt {
        id: polkitPrompt
      }

      GreeterPreview {
        id: greeterPreview
      }
    }
  }
}
