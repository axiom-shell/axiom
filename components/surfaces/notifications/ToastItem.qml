pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications

import qs.config
import qs.services.system
import qs.services.ui
import qs.components.methods
import qs.components.reusable
import qs.components.content.parts.notifications

// One notification's toast in a ToastStack: a card of its own (detached)
// or a row of the stack's one box (attached). It times out, pauses while
// hovered or replied to, swipes away sideways, and runs the
// notification's actions. It slides in from the stack's slide edge and
// leaves as ToastMotion.leave says (the stack removes it once `gone`).
Item {
  id: root

  required property var notification
  // Its history entry's uid ("" for a transient one), taken while it's
  // live: invoking an action can close it
  property string uid: ""
  // A card of its own, else a row of the attached box
  property bool card: true
  // The ScreenEdge it slides in from and out to, "slide" | "fade" | "none"
  property int slideEdge: ScreenEdge.Top
  property string motionStyle: "slide"
  // How far it slides to be out of sight (past its window's edge), and the
  // shift it leaves by (ToastMotion.leave, set as it starts leaving)
  property real hiddenDistance: 0
  property real swipeThreshold: 150
  // A popout is shown over the stack: it slides out of sight, its timer
  // paused, and comes back when that closes (ToastStack.covered)
  property bool covered: false
  onCoveredChanged: {
    if (root.leaving || root.motionStyle === "none") {
      root.opacity = root.covered ? 0 : 1;
      return;
    }
    if (root.covered) {
      enter.stop();
      const to = root._hidden();
      coverX.to = to.x;
      coverY.to = to.y;
      cover.start();
    } else {
      cover.stop();
      enter.start();
    }
  }

  // Leaving: sliding or fading out (the stack keeps it in place meanwhile)
  readonly property bool leaving: leave.running || root.gone
  property bool gone: false
  // Drawn under the toasts nearer the edge as it leaves (ToastMotion.leave)
  property bool tucked: false

  // Out of sight: the stack lets it go
  signal finished
  // The user closed it: the host hides it on every screen
  signal userClosed
  // Timed out: the host hides it here
  signal timedOut

  readonly property bool hovered: hover.hovered
  readonly property bool replying: (replyLoader.item as NotificationReply)?.typing ?? false
  readonly property bool critical: root.notification ? NotificationManager.urgencyOf(root.notification) === NotificationUrgency.Critical : false

  // expireTimeout: 0 is the freedesktop-spec signal for "never expire", a
  // positive one is the app's own duration (ms), -1 leaves it to us
  readonly property bool neverExpires: (NotificationsConfig.followApps && root.notification?.expireTimeout === 0) || (NotificationsConfig.criticalStays && root.critical)
  // (its app's rule's duration first, NotificationsConfig.apps)
  readonly property int _ruleTimeout: root.notification ? NotificationManager.timeoutOf(root.notification) : -1
  readonly property int duration: root._ruleTimeout > 0 ? root._ruleTimeout : NotificationsConfig.followApps && root.notification?.expireTimeout > 0 ? root.notification.expireTimeout : NotificationsConfig.timeout

  // The card's box, for its blur shape (ToastStack)
  readonly property Item box: background
  // Its slide and swipe, for the blur shape to follow
  readonly property real shiftX: slide.x + swipe.x
  readonly property real shiftY: slide.y

  implicitWidth: NotificationsConfig.width
  implicitHeight: Math.min(mainColumn.implicitHeight + Widget.padding * 2, Widget.px(260))
  z: root.tucked ? -1 : 0
  opacity: 0

  // Hides it (the notification stays in the history), as it leaves
  // `index` in the stack (0: the one at its edge), growing as `grow`
  function dismiss(index, grow) {
    if (root.leaving)
      return;
    snapBack.stop();
    const out = ToastMotion.leave(index ?? 0, root.slideEdge, grow ?? ToastMotion.growth(root.slideEdge, 0), root.height, root.hiddenDistance);
    root.tucked = out.tuck && swipe.x === 0;
    if (swipe.x !== 0) {
      // A swipe carries on the way it went, not to the slide edge
      leaveX.to = slide.x + (swipe.x < 0 ? -root.width : root.width);
      leaveY.to = slide.y;
    } else {
      const shift = root.motionStyle === "slide" ? out.shift : Qt.point(0, 0);
      leaveX.to = shift.x;
      leaveY.to = shift.y;
    }
    if (root.motionStyle === "none") {
      root.gone = true;
      root.finished();
      return;
    }
    leave.start();
  }

  // Closed by the user; `remove` also takes it out of the history
  function close(remove) {
    if (root.leaving)
      return;
    if (remove && root.uid)
      NotificationManager.dismiss(root.uid);
    root.userClosed();
  }

  // The shift ({ x, y }) it starts from, hidden past its slide edge
  function _hidden() {
    return root.motionStyle === "slide" ? ToastMotion.hiddenShift(root.slideEdge, root.hiddenDistance) : Qt.point(0, 0);
  }

  Component.onCompleted: {
    if (root.covered) {
      const hidden = root._hidden();
      slide.x = hidden.x;
      slide.y = hidden.y;
      return;
    }
    const from = root._hidden();
    slide.x = from.x;
    slide.y = from.y;
    if (root.motionStyle === "none") {
      slide.x = 0;
      slide.y = 0;
      root.opacity = 1;
      return;
    }
    enter.start();
  }

  transform: [
    Translate {
      id: slide
    },
    Translate {
      id: swipe
    }
  ]

  ParallelAnimation {
    id: enter
    NumberAnimation {
      target: slide
      property: "x"
      to: 0
      duration: Appearance.animNormal
      easing.type: Appearance.easing
    }
    NumberAnimation {
      target: slide
      property: "y"
      to: 0
      duration: Appearance.animNormal
      easing.type: Appearance.easing
    }
    NumberAnimation {
      target: root
      property: "opacity"
      to: 1
      duration: Appearance.animNormal
      easing.type: Appearance.easing
    }
  }

  ParallelAnimation {
    id: cover
    NumberAnimation {
      id: coverX
      target: slide
      property: "x"
      duration: Appearance.animFast
      easing.type: Appearance.easing
    }
    NumberAnimation {
      id: coverY
      target: slide
      property: "y"
      duration: Appearance.animFast
      easing.type: Appearance.easing
    }
    NumberAnimation {
      target: root
      property: "opacity"
      to: 0
      duration: Appearance.animFast
      easing.type: Appearance.easing
    }
  }

  SequentialAnimation {
    id: leave
    ParallelAnimation {
      NumberAnimation {
        id: leaveX
        target: slide
        property: "x"
        duration: Appearance.animNormal
        easing.type: Appearance.easing
      }
      NumberAnimation {
        id: leaveY
        target: slide
        property: "y"
        duration: Appearance.animNormal
        easing.type: Appearance.easing
      }
      NumberAnimation {
        target: root
        property: "opacity"
        to: 0
        duration: Appearance.animNormal
        easing.type: Appearance.easing
      }
    }
    ScriptAction {
      script: {
        root.gone = true;
        root.finished();
      }
    }
  }

  // A swipe short of the threshold: slide back and undo the fade
  ParallelAnimation {
    id: snapBack
    NumberAnimation {
      target: swipe
      property: "x"
      to: 0
      duration: Appearance.animFast
      easing.type: Appearance.easing
    }
    NumberAnimation {
      target: root
      property: "opacity"
      to: 1
      duration: Appearance.animFast
      easing.type: Appearance.easing
    }
  }

  Timer {
    interval: root.duration
    running: !root.neverExpires && !root.hovered && !root.replying && !root.leaving && !root.covered && !dragger.active
    onTriggered: root.timedOut()
  }

  HoverHandler {
    id: hover
  }

  DragHandler {
    id: dragger
    target: null
    yAxis.enabled: false
    onTranslationChanged: {
      if (!active || root.leaving)
        return;
      swipe.x = translation.x;
      root.opacity = 1 - Math.min(1, Math.abs(translation.x) / (root.swipeThreshold * 2));
    }
    onActiveChanged: {
      if (active || root.leaving)
        return;
      if (Math.abs(swipe.x) > root.swipeThreshold)
        root.close(NotificationsConfig.closeRemoves);
      else
        snapBack.start();
    }
  }

  // The card's own box (its fill left to the blur window while that backs
  // it, ToastStack); a row draws none
  Rectangle {
    id: background
    anchors.fill: parent
    visible: root.card
    color: root.backed ? "transparent" : BlurManager.fillOn(Theme.background, root.screenName)
    border.color: root.critical ? Theme.error : Theme.foreground
    border.width: Appearance.borderWidth
    radius: Appearance.borderRadius + 2
  }
  // Set by the stack: the blur window draws its fill, and on which screen
  property bool backed: false
  property string screenName: ""

  // Critical urgency
  Rectangle {
    visible: root.critical
    x: Widget.px(4)
    width: Widget.px(3)
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.margins: Widget.padding
    radius: 1.5
    color: Theme.error
  }

  ColumnLayout {
    id: mainColumn
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Widget.padding
    spacing: Widget.spacing / 2

    RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing

      NotificationAvatar {
        Layout.alignment: Qt.AlignTop
        appIcon: root.notification?.appIcon ?? ""
        desktopEntry: root.notification?.desktopEntry ?? ""
        image: root.notification?.image ?? ""
        size: Widget.px(40)
        badge: true
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        StyledText {
          Layout.fillWidth: true
          text: root.notification?.appName || ""
          textColor: Theme.foregroundAlt
          textSize: Appearance.fontSizeBy(-2)
          font.bold: true
          elide: Text.ElideRight
        }

        NotificationText {
          notification: root.notification
          summaryLines: 2
          bodyLines: 3
          // Without a default action, a click opens its app (as in the
          // history)
          clickable: !!defaultAction || (root.notification?.desktopEntry ?? "") !== ""
          onActivated: {
            NotificationManager.activate(root.notification, root.notification);
            root.close(NotificationsConfig.removeOnClick);
          }
        }
      }

      StyledIconButton {
        Layout.fillWidth: false
        Layout.fillHeight: false
        Layout.preferredWidth: Widget.smallHeight
        Layout.preferredHeight: Widget.smallHeight
        Layout.alignment: Qt.AlignTop

        iconText: "close"
        iconSize: Appearance.fontSizeBy(-2)
        borderRadius: width / 2
        iconColor: Theme.foregroundAlt
        hoverColor: Theme.backgroundHighlight

        onClicked: root.close(NotificationsConfig.closeRemoves)
      }
    }

    NotificationActions {
      notification: root.notification
      onInvoked: root.close(NotificationsConfig.removeOnClick)
    }

    Loader {
      id: replyLoader
      Layout.fillWidth: true
      active: root.notification?.hasInlineReply ?? false
      visible: active
      sourceComponent: NotificationReply {
        notification: root.notification
        onSent: root.close(NotificationsConfig.removeOnClick)
      }
    }
  }
}
