import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "NotificationMatch"

  function test_normalize() {
    compare(NotificationMatch.normalize("Google Chrome"), "google-chrome");
    compare(NotificationMatch.normalize("firefox.desktop"), "firefox");
    compare(NotificationMatch.normalize("app.zen_browser.zen"), "app.zen-browser.zen");
    compare(NotificationMatch.normalize(undefined), "");
  }

  function test_keys() {
    compare(NotificationMatch.keys(["dev.vencord.Vesktop"]), ["dev.vencord.vesktop", "vesktop"]);
    compare(NotificationMatch.keys(["org.telegram.desktop"]), ["org.telegram", "telegram"], "a .desktop suffix goes, as from a desktop file name");
    compare(NotificationMatch.keys(["com.example.App"]), ["com.example.app", "example"], "a generic last part takes the one before");
    compare(NotificationMatch.keys(["signal-desktop"]), ["signal-desktop", "signal"]);
    compare(NotificationMatch.keys(["", null, "kitty", "kitty"]), ["kitty"], "empty names and repeats add nothing");
  }

  function match(entryNames, windowNames) {
    return NotificationMatch.matches(NotificationMatch.keys(entryNames), NotificationMatch.keys(windowNames));
  }

  function test_matches_real_apps() {
    verify(match(["", "Vesktop"], ["dev.vencord.Vesktop"]), "flatpak Electron app sending only its name");
    verify(match(["", "Zen"], ["app.zen_browser.zen"]), "flatpak browser");
    verify(match(["org.telegram.desktop", "Telegram Desktop"], ["org.telegram.desktop"]));
    verify(match(["", "Telegram"], ["org.telegram.desktop"]));
    verify(match(["signal-desktop", "Signal"], ["signal"]));
    verify(match(["google-chrome", "Google Chrome"], ["Google-chrome"]));
    verify(match(["firefox", "Firefox"], ["firefox"]));
  }

  function test_no_false_matches() {
    verify(!match(["kitty", "kitty"], ["foot"]));
    verify(!match(["", "notify-send"], ["kitty"]));
    verify(!match([], ["kitty"]), "an entry with no names matches nothing");
    verify(!match(["org.gnome.Nautilus"], ["org.gnome.Calendar"]), "a shared vendor prefix isn't a match");
  }
}
