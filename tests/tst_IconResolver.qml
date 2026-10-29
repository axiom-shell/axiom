import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "IconResolver"

  // A theme holding `icons`, desktop entries `apps`, and one heuristic match
  function lookup(icons, apps, entries) {
    return {
      "entry": cls => (entries ?? {})[cls] ?? null,
      "exists": name => icons.includes(name),
      "apps": () => apps ?? []
    };
  }

  function test_guessIcon_data() {
    return [
      {
        "tag": "no class",
        "cls": "",
        "icons": [],
        "want": "image-missing"
      },
      {
        "tag": "a desktop entry first",
        "cls": "Code",
        "icons": [],
        "entries": {
          "Code": {
            "icon": "vscode"
          }
        },
        "want": "vscode"
      },
      {
        "tag": "a substitution",
        "cls": "Code",
        "icons": [],
        "want": "visual-studio-code"
      },
      {
        "tag": "a substitution, lowercased",
        "cls": "FootClient",
        "icons": [],
        "want": "foot"
      },
      {
        "tag": "a regex substitution",
        "cls": "steam_app_570",
        "icons": [],
        "want": "steam_icon_570"
      },
      {
        "tag": "the class, if the theme has it",
        "cls": "firefox",
        "icons": ["firefox"],
        "want": "firefox"
      },
      {
        "tag": "lowercased",
        "cls": "Firefox",
        "icons": ["firefox"],
        "want": "firefox"
      },
      {
        "tag": "a reverse domain's last part",
        "cls": "org.gnome.Nautilus",
        "icons": ["nautilus"],
        "want": "nautilus"
      },
      {
        "tag": "spaces to hyphens",
        "cls": "App Name",
        "icons": ["app-name"],
        "want": "app-name"
      },
      {
        "tag": "an entry whose icon contains the class",
        "cls": "Spotify",
        "icons": ["com.spotify.Client"],
        "apps": [
          {
            "name": "Music",
            "icon": "com.spotify.Client"
          }
        ],
        "want": "com.spotify.Client"
      },
      {
        "tag": "an entry whose name contains it",
        "cls": "zed",
        "icons": ["dev.editor"],
        "apps": [
          {
            "name": "Zed",
            "icon": "dev.editor"
          }
        ],
        "want": "dev.editor"
      },
      {
        "tag": "an entry's icon the theme lacks",
        "cls": "zed",
        "icons": [],
        "apps": [
          {
            "name": "Zed",
            "icon": "dev.editor"
          }
        ],
        "want": "zed"
      }
    ];
  }

  function test_guessIcon(data) {
    compare(IconResolver.guessIcon(data.cls, lookup(data.icons, data.apps, data.entries)), data.want);
  }
}
