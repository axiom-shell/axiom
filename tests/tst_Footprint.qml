import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "Footprint"

  function test_persistent_from_field() {
    verify(Footprint.persistent({
      "x-footprint": true
    }, {}, null));
    verify(!Footprint.persistent({
      "type": "boolean"
    }, {}, null));
    verify(!Footprint.persistent({
      "x-footprint": false
    }, {}, null));
    verify(!Footprint.persistent(null, {}, null));
  }

  function test_persistent_from_section() {
    verify(Footprint.persistent({
      "type": "boolean"
    }, {
      "x-footprint": true
    }, null));
    verify(!Footprint.persistent({
      "type": "boolean"
    }, {
      "x-footprint": "yes"
    }, null), "only true on a section");
  }

  function test_persistent_from_hookup() {
    verify(Footprint.persistent({
      "x-hookup": [
        {}
      ]
    }, {}, null));
  }

  function test_persistent_condition() {
    const field = {
      "x-footprint": {
        "/$compositor": ["hyprland", "sway"]
      }
    };
    verify(Footprint.persistent(field, {}, key => ({
          "/$compositor": "sway"
        })[key]));
    verify(!Footprint.persistent(field, {}, key => ({
          "/$compositor": "niri"
        })[key]), "a session effect under niri");
  }

  function test_offValue() {
    compare(Footprint.offValue({
      "type": "boolean",
      "default": true
    }), false);
    compare(Footprint.offValue({
      "type": "string",
      "default": ""
    }), "");
    compare(Footprint.offValue({
      "type": "integer",
      "default": 3
    }), 3);
  }

  function test_groups() {
    const rows = [
      {
        "id": "a",
        "owner": ""
      },
      {
        "id": "b",
        "owner": "ThemeIntegrations.gtk"
      },
      {
        "id": "c",
        "owner": "ThemeIntegrations.kitty"
      },
      {
        "id": "d",
        "owner": "ThemeIntegrations.gtk"
      }
    ];
    const groups = Footprint.groups(rows);
    compare(groups.map(g => g.owner), ["ThemeIntegrations.gtk", "ThemeIntegrations.kitty", ""]);
    compare(groups[0].rows.map(r => r.id), ["b", "d"]);
    compare(groups[2].owner, "", "the compositor's lines last");
    compare(Footprint.groups([]).length, 0);
  }

  function test_label() {
    compare(Footprint.label({
      "kind": "gsetting",
      "target": "org.gnome.desktop.interface color-scheme"
    }, "/home/u"), "gsettings org.gnome.desktop.interface color-scheme");
    compare(Footprint.label({
      "kind": "file",
      "target": "/home/u/.config/kitty/axiom.conf"
    }, "/home/u"), "~/.config/kitty/axiom.conf");
    compare(Footprint.label({
      "kind": "file",
      "target": "/home/u/.local/share/icons/axiom-cursor-X"
    }, "/home/u"), "~/…/share/icons/axiom-cursor-X");
    compare(Footprint.label({
      "kind": "fcitx-config",
      "target": "fcitx://config/global"
    }), "fcitx5 config/global");
    compare(Footprint.label({
      "kind": "mimeapps",
      "target": "/home/u/.config/mimeapps.list",
      "key": "Default Applications/text/html"
    }, "/home/u"), "~/.config/mimeapps.list (text/html)");
  }

  function test_ownerRows() {
    const rows = [
      {
        "id": "a",
        "owner": "S.x"
      },
      {
        "id": "b",
        "owner": "S.x",
        "inferred": true
      },
      {
        "id": "c",
        "owner": "S.x",
        "system": true
      },
      {
        "id": "d",
        "owner": "S.x",
        "inferred": true,
        "system": true
      },
      {
        "id": "e",
        "owner": "S.y"
      },
      {
        "id": "f",
        "owner": ""
      }
    ];
    const x = Footprint.ownerRows(rows, "S.x");
    compare(x.recorded.map(r => r.id), ["a"]);
    compare(x.inferred.map(r => r.id), ["b"]);
    compare(x.system.map(r => r.id), ["c", "d"], "inferred + system is system only");
    compare(Footprint.ownerRows(rows, "S.y").recorded.map(r => r.id), ["e"], "another owner excluded");
    compare(Footprint.ownerRows(rows, "").recorded.map(r => r.id), ["f"]);
    compare(Footprint.ownerRows(rows, "").inferred.length, 0);
    compare(Footprint.ownerRows(null, "S.x").recorded.length, 0);
  }
}
