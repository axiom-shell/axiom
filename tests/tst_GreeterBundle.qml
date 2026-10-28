import QtQuick
import QtTest
import qs.components.methods

TestCase {
  id: test
  name: "GreeterBundle"

  // Records the round trip's fill as a shared fixture (Shared.qml): the
  // binary checks the filled bundle is a valid config
  Shared {
    id: shared
    testCase: test
  }

  readonly property var schema: shared.schema
  readonly property var inputSchema: schema.properties.Input

  function config(mode) {
    const config = SchemaValidation.applyDefaults({}, schema);
    config.Appearance.wallpaper.file = "file:///home/u/Pictures/a.png";
    config.Appearance.wallpaper.perScreen = {
      "DP-1": "file:///home/u/Pictures/a.png",
      "HDMI-A-1": "file:///home/u/Pictures/b.png",
      "DP-2": "file:///home/u/Pictures/gone.png"
    };
    config.Compositor.mode = mode;
    config.Input.keyboard.enabled = mode === "managed";
    config.Input.keyboard.layout = "us,de";
    config.Compositor.hyprland.dimStrength = 9;
    config.Monitors.items = [
      {
        "id": "desk",
        "name": "desk",
        "outputs": [
          {
            "output": "desc:Dell"
          }
        ]
      }
    ];
    config.Chat.keepConversations = 3;
    return config;
  }

  readonly property var copies: ({
      "file:///home/u/Pictures/a.png": "file:///var/lib/axiom-greeter/config/wallpapers/0.png",
      "file:///home/u/Pictures/b.png": "file:///var/lib/axiom-greeter/config/wallpapers/1.png"
    })

  function test_export_takes_only_its_sections() {
    const bundle = GreeterBundle.exportConfig(config("detached"), inputSchema, copies);
    compare(Object.keys(bundle).sort(), ["Appearance", "Compositor", "General", "Greeter", "Input", "Interface", "Monitors", "Weather", "format", "version"]);
    compare(bundle.Monitors.items[0].name, "desk");
    compare(bundle.Compositor, {
      "mode": "detached"
    }, "the compositor's own options stay home");
  }

  function test_export_renames_wallpapers_to_copies() {
    const bundle = GreeterBundle.exportConfig(config("detached"), inputSchema, copies);
    compare(bundle.Appearance.wallpaper.file, "file:///var/lib/axiom-greeter/config/wallpapers/0.png");
    compare(bundle.Appearance.wallpaper.perScreen, {
      "DP-1": "file:///var/lib/axiom-greeter/config/wallpapers/0.png",
      "HDMI-A-1": "file:///var/lib/axiom-greeter/config/wallpapers/1.png"
    });
    compare(GreeterBundle.wallpaperSources(config("detached")), ["file:///home/u/Pictures/a.png", "file:///home/u/Pictures/b.png", "file:///home/u/Pictures/gone.png"]);
  }

  function test_export_takes_only_greeter_options() {
    const bundle = GreeterBundle.exportConfig(config("managed"), inputSchema, copies);
    compare(bundle.Input.keyboard.enabled, true);
    compare(bundle.Input.keyboard.layout, "us,de");
    verify(bundle.Input.mouse.sensitivity !== undefined);
    verify(Object.keys(bundle.Input).every(group => ["keyboard", "mouse", "touchpad", "cursor"].includes(group)), "x-greeter options only");
  }

  // The exported bundle fills to a whole config (valid: the binary's
  // TestSharedSchemaCases validates this fill)
  function test_export_round_trips() {
    const bundle = GreeterBundle.exportConfig(config("managed"), inputSchema, copies);
    const filled = shared.applyDefaults(bundle, schema);
    compare(filled.Chat.keepConversations, schema.properties.Chat.properties.keepConversations.default);
  }
}
