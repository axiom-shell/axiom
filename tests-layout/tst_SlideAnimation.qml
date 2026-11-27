import QtQuick
import QtTest
import qs.components.hosts.popout

// SlideAnimation: the states own where it slides, from its place (slideX,
// slideY) and its opacity, so a surface made hidden follows its size while
// hidden and its first open slides from where every later one does.
TestCase {
  id: root

  name: "SlideAnimation"
  when: windowShown
  visible: true
  width: 400
  height: 400

  Harness {
    id: harness
  }

  Component {
    id: slideComp

    SlideAnimation {
      animationDuration: 100
    }
  }

  // A bar's request taker, keeping the last request it was sent
  Component {
    id: stubComp

    QtObject {
      property var last: null
      // one pill at rest, which a stretch stands on
      property var pillRects: [
        {
          "start": 20,
          "length": 20
        }
      ]
      function setRequest(owner, request) {
        last = request;
      }
    }
  }

  Component {
    id: stretchComp

    PillStretch {
      owner: "t"
      open: true
    }
  }

  function initTestCase() {
    harness.configure({});
  }

  function make(props) {
    return createTemporaryObject(slideComp, root, props);
  }

  function test_madeHidden() {
    const s = make({
      "slideFromRight": true,
      "width": 100,
      "height": 50
    });
    compare(s.slideX, 100);
    wait(50);
    compare(s.slideX, 100);
  }

  function test_madeShown() {
    const s = make({
      "slideFromRight": true,
      "width": 100,
      "height": 50,
      "active": true
    });
    compare(s.slideX, 0);
    wait(50);
    compare(s.slideX, 0);
  }

  function test_madeHiddenShownAtOnce() {
    const s = make({
      "slideFromRight": true,
      "width": 100,
      "height": 50
    });
    s.active = true;
    compare(s.slideX, 100);
    tryCompare(s, "slideX", 0, 1000);
  }

  function growsWhileHidden(props, prop, size, sizeProp) {
    const s = make(Object.assign({
      "width": 0,
      "height": 0
    }, props));
    wait(50);
    s[sizeProp] = size;
    compare(s[prop], size);
    s.active = true;
    compare(s[prop], size);
    tryCompare(s, prop, 0, 1000);
  }

  function test_growsWhileHidden() {
    growsWhileHidden({
      "slideFromRight": true
    }, "slideX", 120, "width");
  }

  function test_growsWhileHiddenBottom() {
    growsWhileHidden({
      "slideFromBottom": true
    }, "slideY", 120, "height");
  }

  function test_growsWhileHiddenFade() {
    const s = make({
      "fade": true,
      "width": 0,
      "height": 0
    });
    wait(50);
    s.width = 120;
    compare(s.shownOpacity, 0);
    compare(s.slideX, 0);
    s.active = true;
    tryCompare(s, "shownOpacity", 1, 1000);
    compare(s.slideX, 0);
    compare(s.slideY, 0);
  }

  function test_sideOverflow_data() {
    return [
      {
        "tag": "slides down, room beside it",
        "props": {
          "slideFromTop": true,
          "overflow": 2,
          "startOverflow": 3,
          "endOverflow": 1
        },
        "want": [3, 0, 2, 2]
      },
      {
        "tag": "slides sideways, room above and below",
        "props": {
          "slideFromLeft": true,
          "startOverflow": 1,
          "endOverflow": 1
        },
        "want": [0, 1, 0, 1]
      },
      {
        "tag": "no side room",
        "props": {
          "slideFromBottom": true,
          "overflow": 4
        },
        "want": [4, 4, 4, 0]
      }
    ];
  }
  function test_sideOverflow(data) {
    const s = make(data.props);
    compare([s._left, s._top, s._right, s._bottom], data.want);
  }

  function test_firstOpenMatchesLater() {
    const s = make({
      "slideFromRight": true,
      "width": 0,
      "height": 0
    });
    wait(50);
    s.width = 120;
    s.active = true;
    const first = s.slideX;
    compare(first, 120);
    tryCompare(s, "slideX", 0, 1000);
    s.active = false;
    tryCompare(s, "slideX", 120, 1000);
    s.active = true;
    compare(s.slideX, first);
  }

  // A pill's end reach and opening are sent in the pass they change in, so
  // the bar draws them in the frame their surface moves in
  function test_pillRequestSentInItsPass() {
    const stub = createTemporaryObject(stubComp, root);
    const stretch = createTemporaryObject(stretchComp, root, {
      "container": stub
    });
    stretch.endReach = {
      "atStart": true,
      "to": 40
    };
    compare(stub.last?.endReach?.to, 40);
    stretch.endReach = {
      "atStart": true,
      "to": 55
    };
    compare(stub.last?.endReach?.to, 55);
    stretch.opening = {
      "start": 0,
      "end": 30
    };
    compare(stub.last?.opening?.end, 30);
  }

  // A stretch that tracks its surface is sent in the pass it changes in too
  function test_trackingStretchSentInItsPass() {
    const stub = createTemporaryObject(stubComp, root);
    const stretch = createTemporaryObject(stretchComp, root, {
      "container": stub,
      "tracks": true
    });
    stretch.stretch = {
      "index": 0,
      "start": 10,
      "end": 50
    };
    verify(stub.last?.stretch);
    compare(stub.last.stretch.start, 10);
    compare(stub.last.stretch.end, 50);
  }
}
