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
}
