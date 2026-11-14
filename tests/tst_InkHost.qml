import QtQuick
import QtQuick.Controls
import QtTest
import qs.components.methods

// InkHost.find: the nearest ancestor with an `inkScope`, in the binding form
// StyledText uses (a fake text is an Item reading it from its parent). The
// pieces themselves import Quickshell and stay out of this pure run.
TestCase {
  id: root

  name: "InkHost"
  when: windowShown

  Component {
    id: hostComp

    Item {
      property var inkScope: "a"
    }
  }

  Component {
    id: textComp

    Item {
      readonly property var host: InkHost.find(parent)
    }
  }

  Component {
    id: loaderComp

    Item {
      property var inkScope: "loader"
      property alias loader: loader

      Loader {
        id: loader

        sourceComponent: textComp
      }
    }
  }

  Component {
    id: repeaterComp

    Item {
      property var inkScope: "rep"
      property alias repeater: repeater

      Repeater {
        id: repeater

        model: 1
        delegate: textComp
      }
    }
  }

  Component {
    id: viewComp

    Item {
      property var inkScope: "view"
      property alias view: view

      ListView {
        id: view

        width: 100
        height: 100
        model: 2
        delegate: textComp
      }
    }
  }

  Component {
    id: popupComp

    Item {
      property var inkScope: "popup"
      property alias popup: popup

      Popup {
        id: popup

        contentItem: Item {
          readonly property var host: InkHost.find(parent)
        }
      }
    }
  }

  function test_nearest_wins() {
    const outer = createTemporaryObject(hostComp, root);
    outer.inkScope = "outer";
    const inner = hostComp.createObject(outer);
    inner.inkScope = "inner";
    const text = textComp.createObject(inner);
    compare(text.host, inner);
    compare(InkHost.find(outer), outer);
  }

  function test_none() {
    compare(InkHost.find(null), null);
    const plain = createTemporaryObject(textComp, root);
    compare(plain.host, null);
  }

  function test_repeater_loader_listview() {
    const rep = createTemporaryObject(repeaterComp, root);
    compare(rep.repeater.itemAt(0).host, rep);
    const ld = createTemporaryObject(loaderComp, root);
    tryVerify(() => ld.loader.item !== null);
    compare(ld.loader.item.host, ld);
    const view = createTemporaryObject(viewComp, root);
    tryVerify(() => view.view.itemAtIndex(0) !== null);
    compare(view.view.itemAtIndex(0).host, view);
  }

  function test_popup_content_finds_none() {
    const holder = createTemporaryObject(popupComp, root);
    holder.popup.open();
    tryVerify(() => holder.popup.opened);
    compare(holder.popup.contentItem.host, null);
    holder.popup.close();
  }

  // The ancestor case: a text held by an item created with no parent finds
  // nothing, then the host once its holder is reparented into it, and
  // nothing again after it moves out
  function test_reparent_reruns() {
    const host = createTemporaryObject(hostComp, root);
    const holder = createTemporaryObject(textComp, null);
    const text = textComp.createObject(holder);
    compare(text.host, null);
    holder.parent = host;
    compare(text.host, host);
    holder.parent = null;
    compare(text.host, null);
    holder.destroy();
  }

  Component {
    id: relayComp

    Item {
      id: relay

      property var above: null
      readonly property var inkHostAbove: InkHost.find(relay.parent)
    }
  }

  Component {
    id: countComp

    Item {
      id: counted

      property int evals: 0
      readonly property var host: {
        counted.evals++;
        return InkHost.find(counted.parent);
      }
    }
  }

  // A relay answers for the host above it: its own inkHostAbove, null or a
  // host, without the walk going on
  function test_stops_at_relay() {
    const outer = createTemporaryObject(hostComp, root);
    const mid = hostComp.createObject(outer);
    mid.inkScope = "mid";
    const relayNull = createTemporaryObject(relayComp, null);
    const holder = textComp.createObject(relayNull);
    compare(holder.host, null);
    const relayHost = relayComp.createObject(mid);
    compare(relayHost.inkHostAbove, mid);
    const text = textComp.createObject(relayHost);
    compare(text.host, mid);
    // a relay with no host above hides the Surface that is further up it
    const relayNone = relayComp.createObject(outer);
    relayNone.parent = null;
    const probe = textComp.createObject(relayNone);
    compare(probe.host, null);
    relayNull.destroy();
  }

  function test_scope_below_relay_wins() {
    const outer = createTemporaryObject(hostComp, root);
    const relay = relayComp.createObject(outer);
    const inner = hostComp.createObject(relay);
    inner.inkScope = "inner";
    const text = textComp.createObject(inner);
    compare(text.host, inner);
  }

  function test_relay_follows_reparent() {
    const hostA = createTemporaryObject(hostComp, root);
    const holder = createTemporaryObject(textComp, null);
    const relay = relayComp.createObject(holder);
    const text = textComp.createObject(relay);
    compare(relay.inkHostAbove, null);
    compare(text.host, null);
    holder.parent = hostA;
    compare(relay.inkHostAbove, hostA);
    compare(text.host, hostA);
    holder.parent = null;
    compare(text.host, null);
    holder.destroy();
  }

  // A relay and a child binding built in one Component: the child's first
  // value is already right and it evaluates once
  Component {
    id: orderComp

    Item {
      id: top

      property var inkScope: "top"

      Item {
        id: relay

        readonly property var inkHostAbove: InkHost.find(relay.parent)

        Item {
          id: child

          property int evals: 0
          property int undefinedSeen: 0
          readonly property var host: {
            child.evals++;
            const h = InkHost.find(child.parent);
            if (h === undefined)
              child.undefinedSeen++;
            return h;
          }
        }
      }
    }
  }

  function test_relay_order_in_one_component() {
    const top = createTemporaryObject(orderComp, root);
    const child = top.children[0].children[0];
    compare(child.host, top);
    compare(child.evals, 1);
    compare(child.undefinedSeen, 0);
  }
}
