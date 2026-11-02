import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "DriveInfo"

  function vol(id, extra) {
    return Object.assign({
      "id": id,
      "device": "/dev/" + id,
      "label": "",
      "uuid": "",
      "fsType": "vfat",
      "size": 0,
      "mountPoints": [],
      "readOnly": false,
      "encrypted": false,
      "unlocked": false,
      "cleartextId": "",
      "mountable": true
    }, extra ?? {});
  }

  function drive(volumes, extra) {
    return Object.assign({
      "id": "d1",
      "vendor": "SanDisk",
      "model": "Ultra",
      "size": 32000000000,
      "bus": "usb",
      "optical": false,
      "removable": true,
      "canEject": true,
      "canPowerOff": true,
      "volumes": volumes
    }, extra ?? {});
  }

  function test_size() {
    compare(DriveInfo.size(32000000000), "32 GB");
    compare(DriveInfo.size(7800000000), "7.8 GB");
    compare(DriveInfo.size(512000000), "512 MB");
    compare(DriveInfo.size(2000000000000), "2.0 TB");
    compare(DriveInfo.size(0), "", "unknown");
  }

  function test_name() {
    compare(DriveInfo.name(drive([vol("a")])), "SanDisk Ultra", "no label: vendor and model");
    compare(DriveInfo.name(drive([vol("a", {
        "label": "STICK"
      })])), "STICK", "one labelled volume");
    compare(DriveInfo.name(drive([vol("a", {
        "label": "ONE"
      }), vol("b", {
        "label": "TWO"
      })])), "SanDisk Ultra", "two labels: the hardware");
    compare(DriveInfo.name(drive([], {
      "vendor": "",
      "model": ""
    })), "", "nothing to name it by");
    compare(DriveInfo.displayName(drive([vol("a")])), "SanDisk Ultra · 32 GB");
    compare(DriveInfo.displayName(drive([], {
      "vendor": "",
      "model": "",
      "size": 0
    }), "Drive"), "Drive", "the fallback");
    compare(DriveInfo.hardware(drive([vol("a", {
        "label": "STICK"
      })])), "SanDisk Ultra");
    compare(DriveInfo.hardware(drive([vol("a")])), "", "already the name");
  }

  function test_icon() {
    compare(DriveInfo.icon(drive([])), "usb");
    compare(DriveInfo.icon(drive([], {
      "bus": "sdio"
    })), "sd_card");
    compare(DriveInfo.icon(drive([], {
      "model": "SD Card Reader"
    })), "sd_card", "a card reader on USB");
    compare(DriveInfo.icon(drive([], {
      "optical": true
    })), "album");
    compare(DriveInfo.icon(drive([], {
      "bus": "loop"
    })), "hard_drive");
  }

  function test_volumes() {
    const d = drive([vol("luks", {
        "encrypted": true,
        "mountable": false
      }), vol("swap", {
        "mountable": false
      })]);
    compare(DriveInfo.volumes(d).map(v => v.id), ["luks"], "a locked container shows; unmountable left out");
  }

  function test_effective() {
    const d = drive([vol("luks", {
        "encrypted": true,
        "unlocked": true,
        "cleartextId": "clear",
        "mountable": true
      })]);
    const v = DriveInfo.effective(d.volumes[0]);
    compare(v.id, "clear", "the cleartext, by its id");
    compare(DriveInfo.action(d.volumes[0]), "mount");
    const mounted = drive([vol("luks", {
        "encrypted": true,
        "unlocked": true,
        "cleartextId": "clear",
        "mountable": true,
        "mountPoints": ["/run/media/u/x"]
      })]);
    compare(DriveInfo.action(mounted.volumes[0]), "open", "the container reports its cleartext's mount points");
    verify(DriveInfo.driveMounted(mounted));
    compare(DriveInfo.mountPoint(mounted), "/run/media/u/x");
    const lvm = drive([vol("luks", {
        "encrypted": true,
        "unlocked": true,
        "cleartextId": "clear",
        "mountable": false
      })]);
    compare(DriveInfo.action(lvm.volumes[0]), "", "no filesystem inside (LVM): nothing to mount");
  }

  function test_action() {
    const locked = vol("l", {
      "encrypted": true,
      "mountable": false
    });
    const d = drive([locked, vol("m", {
        "mountPoints": ["/m"]
      }), vol("u")]);
    compare(DriveInfo.action(locked), "unlock");
    compare(DriveInfo.action(d.volumes[1]), "open");
    compare(DriveInfo.action(d.volumes[2]), "mount");
    verify(DriveInfo.driveLocked(d));
  }

  function test_mountedIds() {
    const mounted = vol("m", {
      "mountPoints": ["/m"]
    });
    compare(DriveInfo.mountedIds(drive([mounted, vol("u")]), []), ["m"], "mounted now");
    compare(DriveInfo.mountedIds(drive([vol("m"), vol("u")]), ["m"]), [], "unmounted in place");
    compare(DriveInfo.mountedIds(drive([vol("u")]), ["m"]), ["m"], "gone while mounted: a pull");
    compare(DriveInfo.mountedIds(drive([]), []), [], "gone while not mounted");
    compare(DriveInfo.mountedIds(drive([mounted]), ["m"]), ["m"], "no duplicate");
    const luks = vol("c", {
      "encrypted": true,
      "unlocked": true,
      "cleartextId": "x",
      "mountPoints": ["/x"]
    });
    compare(DriveInfo.mountedIds(drive([luks]), []), ["c"], "an unlocked container by its own id");
    compare(DriveInfo.mountedIds(drive([]), ["c"]), ["c"], "its container gone");
  }

  function test_pick() {
    const locked = vol("l", {
      "encrypted": true,
      "mountable": false
    });
    compare(DriveInfo.pick(drive([locked, vol("u"), vol("m", {
        "mountPoints": ["/m"]
      })])).volume.id, "m", "mounted first");
    const p = DriveInfo.pick(drive([locked, vol("u")]));
    compare([p.volume.id, p.action], ["u", "mount"], "then one to mount");
    compare(DriveInfo.pick(drive([locked])).action, "unlock", "then one to unlock");
    compare(DriveInfo.pick(drive([])), null, "nothing");
  }

  function test_clickAction() {
    compare(DriveInfo.clickAction("mounted"), "open");
    compare(DriveInfo.clickAction("locked"), "unlock");
    for (const kind of ["added", "unmounted", "ejected", "removed", "pulled", "busy", "ejectFailed", undefined])
      compare(DriveInfo.clickAction(kind), "show", String(kind));
  }

  function test_ignored() {
    const d = drive([vol("a", {
        "uuid": "1234-ABCD",
        "label": "BACKUP"
      })]);
    verify(DriveInfo.ignored(d, ["1234-ABCD"]), "by UUID");
    verify(DriveInfo.ignored(d, ["BACKUP"]), "by label");
    verify(!DriveInfo.ignored(d, ["backup"]), "exactly");
    verify(!DriveInfo.ignored(d, [""]), "an empty entry matches nothing");
    verify(!DriveInfo.ignored(drive([vol("b")]), ["1234-ABCD"]));
    verify(!DriveInfo.ignored(d, []));
  }
}
