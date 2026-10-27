import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "Packages"

  function test_distroFamily_data() {
    return [
      {
        "tag": "arch",
        "text": 'NAME="Arch Linux"\nID=arch\nBUILD_ID=rolling',
        "want": "arch"
      },
      {
        "tag": "cachyos",
        "text": 'NAME="CachyOS Linux"\nID="cachyos"\nID_LIKE="arch"',
        "want": "arch"
      },
      {
        "tag": "manjaro",
        "text": "ID=manjaro\nID_LIKE=arch",
        "want": "arch"
      },
      {
        "tag": "fedora",
        "text": 'NAME="Fedora Linux"\nVERSION_ID=44\nID=fedora',
        "want": "fedora"
      },
      {
        "tag": "nobara",
        "text": 'ID=nobara\nID_LIKE="rhel centos fedora"',
        "want": "fedora"
      },
      {
        "tag": "ubuntu",
        "text": "ID=ubuntu\nID_LIKE=debian",
        "want": ""
      },
      {
        "tag": "empty",
        "text": null,
        "want": ""
      }
    ];
  }

  function test_distroFamily(data) {
    compare(Packages.distroFamily(data.text), data.want);
  }

  // Each key names every distribution, so a new one can't be half added
  function test_everyKeyNamesEveryDistro() {
    for (const key of Object.keys(Packages.packages))
      for (const distro of Object.keys(Packages.distros))
        verify(Packages.packages[key][distro] !== undefined, `${key} has no ${distro} entry`);
  }

  function test_packageFor() {
    compare(Packages.packageFor("arch", "qalc"), {
      "name": "libqalculate"
    });
    compare(Packages.packageFor("fedora", "qalc"), {
      "name": "qalculate"
    });
    compare(Packages.packageFor("fedora", "satty"), {
      "name": "satty",
      "repo": "nett00n/hyprland"
    });
    compare(Packages.packageFor("fedora", "checkupdates"), null, "Arch only");
    compare(Packages.packageFor("arch", "foot"), {
      "name": "foot"
    }, "an unlisted command: its own name");
    compare(Packages.packageFor("", "qalc"), null, "unknown distribution");
  }

  function test_applies() {
    verify(Packages.applies("arch", "checkupdates"));
    verify(!Packages.applies("fedora", "checkupdates"));
    verify(Packages.applies("", "checkupdates"), "unknown distribution: shown");
  }

  function test_installLines_arch() {
    compare(Packages.installLines("arch", ["iconFont", "qalc", "grim", "qalc"]), ["sudo pacman -S --needed ttf-material-symbols-variable libqalculate grim"]);
    compare(Packages.installLines("arch", []), []);
  }

  function test_installLines_fedora() {
    const lines = Packages.installLines("fedora", ["satty", "qalc", "checkupdates", "iconFont"]);
    compare(lines.length, 3);
    compare(lines[0], "sudo dnf copr enable -y nett00n/hyprland", "the COPR first, once");
    compare(lines[1], "sudo dnf install satty qalculate", "checkupdates dropped");
    verify(lines[2].startsWith("mkdir -p ~/.local/share/fonts && curl -fLo ~/.local/share/fonts/MaterialSymbolsRounded.ttf '"), lines[2]);
    verify(lines[2].endsWith("' && fc-cache -f"), lines[2]);
    compare(Packages.installLines("fedora", ["qalc"]), ["sudo dnf install qalculate"], "no COPR unless needed");
    compare(Packages.installLines("fedora", ["checkupdates"]), [], "nothing to install");
  }

  // niri and sway run X11 apps only with these (Hyprland's package pulls Xwayland in)
  function test_x11Helpers() {
    compare(Packages.installLines("arch", ["xwayland-satellite", "Xwayland"]), ["sudo pacman -S --needed xwayland-satellite xorg-xwayland"]);
    compare(Packages.installLines("fedora", ["xwayland-satellite", "Xwayland"]), ["sudo dnf install xwayland-satellite xorg-x11-server-Xwayland"]);
  }

  // Python modules ("py:<module>") from each distribution's own repositories
  function test_pythonModules() {
    compare(Packages.installCommand("arch", ["py:gi"]), "sudo pacman -S --needed python-gobject");
    compare(Packages.installCommand("fedora", ["py:gi"]), "sudo dnf install python3-gobject", "no COPR");
  }

  // What install.sh installs: the compositors, and quickshell from its own
  // COPR on Fedora (beside the Hyprland one, when both are needed)
  function test_installerKeys() {
    compare(Packages.installCommand("arch", ["quickshell", "niri", "nmcli", "py:gi"]), "sudo pacman -S --needed quickshell niri networkmanager python-gobject");
    compare(Packages.installLines("fedora", ["quickshell", "hyprland", "sway"]), ["sudo dnf copr enable -y errornointernet/quickshell", "sudo dnf copr enable -y nett00n/hyprland", "sudo dnf install quickshell hyprland sway"]);
    compare(Packages.packageFor("fedora", "awww"), null, "not packaged for Fedora");
  }

  function test_unknownDistro() {
    compare(Packages.installLines("", ["qalc"]), []);
    compare(Packages.installCommand("", "qalc"), "");
  }

  function test_installCommand() {
    compare(Packages.installCommand("arch", "satty"), "sudo pacman -S --needed satty");
    compare(Packages.installCommand("fedora", "satty"), "sudo dnf copr enable -y nett00n/hyprland && sudo dnf install satty");
    compare(Packages.installCommand("arch", ["greetd", "agreety"]), "sudo pacman -S --needed greetd greetd-agreety");
    compare(Packages.installCommand("fedora", ["greetd", "agreety"]), "sudo dnf install greetd", "agreety ships in greetd");
  }

  // Every distribution checks for updates, each with its own format
  function test_updates() {
    for (const distro of Object.keys(Packages.distros)) {
      const updates = Packages.updates(distro);
      verify(updates !== null, distro);
      verify(updates.check.length > 0 && updates.upgrade !== "" && updates.found.length > 0, distro);
      verify(["pacman", "dnf"].includes(updates.format), distro + ": a format axiom's updates topic parses");
    }
    compare(Packages.updates(""), null, "unknown distribution");
    verify(Packages.updates("arch").aur);
    verify(!Packages.updates("fedora").aur);
  }
}
