import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "GreeterSessions"

  function test_exec_argv_data() {
    return [
      {
        "tag": "plain",
        "exec": "/usr/bin/start-hyprland",
        "expected": ["/usr/bin/start-hyprland"]
      },
      {
        "tag": "words",
        "exec": "uwsm start -e -D Hyprland hyprland.desktop",
        "expected": ["uwsm", "start", "-e", "-D", "Hyprland", "hyprland.desktop"]
      },
      {
        "tag": "quoted",
        "exec": "sh -c \"echo \\\"hi\\\" \\$HOME\"  x",
        "expected": ["sh", "-c", "echo \"hi\" $HOME", "x"]
      },
      {
        "tag": "empty quotes",
        "exec": "run \"\" end",
        "expected": ["run", "", "end"]
      },
      {
        "tag": "field codes",
        "exec": "app %U --percent=50%% %f",
        "expected": ["app", "--percent=50%"]
      },
      {
        "tag": "nothing",
        "exec": "   ",
        "expected": []
      }
    ];
  }

  function test_exec_argv(data) {
    compare(GreeterSessions.execArgv(data.exec), data.expected);
  }

  function test_parse() {
    const session = GreeterSessions.parse(["[Desktop Entry]", "Name=Plasma (Wayland)", "Name[de]=Plasma (Wayland, de)", "Comment=Plasma by KDE", "Exec=/usr/lib/plasma-dbus-run-session-if-needed /usr/bin/startplasma-wayland", "DesktopNames=KDE;Plasma;", "", "[Desktop Action Other]", "Exec=other"].join("\n"), "plasma");
    compare(session.id, "plasma");
    compare(session.name, "Plasma (Wayland)");
    compare(session.exec, ["/usr/lib/plasma-dbus-run-session-if-needed", "/usr/bin/startplasma-wayland"]);
    compare(session.desktopNames, ["KDE", "Plasma"]);
  }

  function test_parse_skips_hidden_and_execless() {
    compare(GreeterSessions.parse("[Desktop Entry]\nName=A\nExec=a\nHidden=true", "a"), null);
    compare(GreeterSessions.parse("[Desktop Entry]\nName=A\nExec=a\nNoDisplay=true", "a"), null);
    compare(GreeterSessions.parse("[Desktop Entry]\nName=A", "a"), null);
    compare(GreeterSessions.parse("not a desktop file", "a"), null);
    // No name: its id
    compare(GreeterSessions.parse("[Desktop Entry]\nExec=niri-session", "niri").name, "niri");
  }

  function test_files() {
    compare(GreeterSessions.files(["/data/wayland-sessions/hyprland.desktop", "/usr/share/wayland-sessions/niri.desktop", "/usr/share/wayland-sessions/hyprland.desktop"]), [
      {
        "id": "hyprland",
        "file": "/data/wayland-sessions/hyprland.desktop"
      },
      {
        "id": "niri",
        "file": "/usr/share/wayland-sessions/niri.desktop"
      }
    ], "the first of each id wins");
    compare(GreeterSessions.files([]), []);
  }

  function test_sorted_and_environment() {
    const niri = GreeterSessions.parse("[Desktop Entry]\nName=Niri\nExec=niri-session\nDesktopNames=niri", "niri");
    const hypr = GreeterSessions.parse("[Desktop Entry]\nName=Hyprland\nExec=start-hyprland\nDesktopNames=Hyprland", "hyprland");
    const bare = GreeterSessions.parse("[Desktop Entry]\nName=Bare\nExec=bare", "bare");
    compare(GreeterSessions.sorted([niri, null, hypr]).map(session => session.id), ["hyprland", "niri"]);
    compare(GreeterSessions.environment(hypr), ["XDG_SESSION_TYPE=wayland", "XDG_CURRENT_DESKTOP=Hyprland", "XDG_SESSION_DESKTOP=hyprland"]);
    compare(GreeterSessions.environment(bare)[1], "XDG_CURRENT_DESKTOP=Bare");
  }
}
