import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "ScreenShareSources"

  function test_hookupTargets() {
    const hypr = ScreenShareSources.hookupTargets("hyprland", "/usr/bin/axiom");
    compare(hypr.length, 1);
    compare(hypr[0].file, "{config}/hypr/xdph.conf");
    compare(hypr[0].text, "screencopy:custom_picker_binary = /usr/bin/axiom", "xdph runs the binary itself, without arguments");
    const sway = ScreenShareSources.hookupTargets("sway", "/usr/bin/axiom");
    compare(sway[0].section, "screencast");
    compare(sway[0].text, "chooser_type = dmenu\nchooser_cmd = '/usr/bin/axiom' screenshare-pick --for xdpw");
    // niri has no hookup: the daemon adds its portal line while axiom runs
    compare(ScreenShareSources.hookupTargets("niri", "/usr/bin/axiom"), []);
    compare(ScreenShareSources.hookupTargets("", "/usr/bin/axiom"), []);
  }

  function test_busNames() {
    compare(ScreenShareSources.portal("hyprland").busName, "org.freedesktop.impl.portal.desktop.hyprland");
    compare(ScreenShareSources.portal("sway").busName, "org.freedesktop.impl.portal.desktop.wlr");
    compare(ScreenShareSources.portal("niri").busName, "org.freedesktop.impl.portal.desktop.gnome");
  }

  function test_portal() {
    compare(ScreenShareSources.portal("niri").package, "xdg-desktop-portal-gnome");
    compare(ScreenShareSources.portal("labwc"), null);
  }

  function test_windowTiles() {
    const windows = [
      {
        "id": "0x55d4",
        "title": "Terminal",
        "appId": "kitty"
      },
      {
        "id": "0x77",
        "title": "Same",
        "appId": "a"
      },
      {
        "id": "0x78",
        "title": "Same",
        "appId": "b"
      }
    ];
    const tiles = ScreenShareSources.windowTiles({
      "windows": [
        {
          "token": "12",
          "id": "0x55d4",
          "title": "",
          "appId": ""
        },
        {
          "token": "3f2a",
          "title": "Terminal"
        },
        {
          "token": "9",
          "title": "Same"
        },
        {
          "token": "10",
          "title": "Same",
          "appId": "b"
        },
        {
          "token": "11",
          "title": "Gone"
        }
      ]
    }, windows);
    compare(tiles[0].match.id, "0x55d4", "by id");
    compare(tiles[0].title, "Terminal", "the title from the match");
    compare(tiles[0].appId, "kitty");
    compare(tiles[1].match.id, "0x55d4", "by title");
    compare(tiles[2].match, null, "two windows have that title");
    compare(tiles[3].match.id, "0x78", "the app tells them apart");
    compare(tiles[4].match, null);
    compare(ScreenShareSources.windowTiles(null, windows), []);
  }

  function test_initialChoice() {
    const request = {
      "outputs": [
        {
          "name": "DP-1"
        },
        {
          "name": "HDMI-A-1"
        }
      ],
      "windows": [
        {
          "token": "7"
        }
      ]
    };
    compare(ScreenShareSources.initialChoice(request, "HDMI-A-1"), {
      "kind": "screen",
      "output": "HDMI-A-1"
    });
    compare(ScreenShareSources.initialChoice(request, "eDP-1").output, "DP-1");
    compare(ScreenShareSources.initialChoice({
      "outputs": [],
      "windows": [
        {
          "token": "7"
        }
      ]
    }, "DP-1"), {
      "kind": "window",
      "window": "7"
    });
    compare(ScreenShareSources.initialChoice({
      "outputs": [],
      "windows": []
    }, "DP-1"), null);
  }
}
