import QtQuick
import QtTest
import qs.config
import qs.components.reusable
import qs.services.ui

// ModalCard, the one card of every modal: it pads its content by
// Style.space5, reveals by fade and slide, draws the accent border only while
// asking, and registers its window as a modal for as long as it exists.
TestCase {
  id: root

  name: "ModalCard"
  when: windowShown
  visible: true
  width: 500
  height: 400

  Harness {
    id: harness
  }

  Component {
    id: cardComp

    ModalCard {
      width: 300
      height: 200

      Rectangle {
        objectName: "fill"
        width: parent.width
        height: parent.height
        color: "red"
      }
    }
  }

  function test_content_is_inset_by_padding() {
    for (const scale of [80, 100, 150]) {
      harness.configure({
        "scale": scale
      });
      const card = createTemporaryObject(cardComp, root);
      const fill = card.children[card.children.length - 1].children[0];
      compare(card.padding, Style.space5, "scale " + scale);
      const origin = fill.mapToItem(card, 0, 0);
      compare(origin.x, card.padding, "scale " + scale + ": left inset");
      compare(origin.y, card.padding, "scale " + scale + ": top inset");
      compare(fill.width, card.width - card.padding * 2, "scale " + scale + ": width");
      compare(fill.height, card.height - card.padding * 2, "scale " + scale + ": height");
    }
  }

  function test_asking_border_and_reveal() {
    harness.configure({});
    const card = createTemporaryObject(cardComp, root);
    compare(card.border.color, Style.borderSubtle);
    card.asking = true;
    compare(card.border.color, Style.accent);
    card.shown = true;
    tryCompare(card, "opacity", 1);
    tryCompare(card, "reveal", 1);
    card.shown = false;
    tryCompare(card, "opacity", 0);
    tryCompare(card, "reveal", 0);
  }

  function test_registers_its_window() {
    harness.configure({});
    const win = Qt.createQmlObject("import QtQuick; QtObject {}", root);
    const card = createTemporaryObject(cardComp, root, {
      "window": win
    });
    verify(SurfaceManager.modals.includes(win), "registered while it exists");
    card.destroy();
    tryVerify(() => !SurfaceManager.modals.includes(win), 1000, "unregistered after");
  }
}
