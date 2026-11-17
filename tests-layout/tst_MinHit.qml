import QtQuick
import QtTest
import qs.config
import qs.components.reusable

// Style.minHit, the one floor for a small icon button's hit square (the notification
// and attachment close buttons): never under the small control height, nor under the
// glyph with a gap each side, at every density and scale.
TestCase {
  id: root

  name: "MinHit"
  when: windowShown
  visible: true
  width: 400
  height: 200

  Harness {
    id: harness
  }

  Component {
    id: buttonComp

    StyledIconButton {
      iconText: "close"
    }
  }

  function test_floor_per_density_and_scale() {
    for (const density of ["compact", "normal", "roomy"]) {
      for (const scale of [80, 100, 150]) {
        harness.configure({
          "density": density,
          "scale": scale
        });
        const row = density + " " + scale;
        for (const icon of [Style.iconXs, Style.iconSm]) {
          const hit = Style.minHit(icon);
          verify(hit >= Widget.smallHeight, row + ": not under the small height");
          verify(hit >= icon + Widget.spacing * 2, row + ": the glyph keeps a gap each side");
          const button = createTemporaryObject(buttonComp, root, {
            "size": hit,
            "iconSize": icon
          });
          compare(button.width, hit, row + ": the button is the hit square wide");
          compare(button.height, hit, row + ": and as high");
          verify(button.width > icon, row + ": the hit square holds its glyph");
        }
      }
    }
  }
}
