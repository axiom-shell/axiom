pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Widgets
import qs.config
import qs.services.system
import qs.components.reusable
import qs.components.content.parts
import qs.components.content.base

// The active media player over a blurred copy of its cover: art, track
// info, a seek bar and controls. As the Media widget's popout: art beside
// the track info, the controls beneath, at a fixed size so track changes
// never resize it. As an overlay card: art beside everything when wide
// (by px: an edge menu's units aren't square), stacked when square or
// tall; a short slot drops the player name, album
// and times; a tall wide one has larger text and controls, centred beside
// the art; a strip is one row (art, title, artist and the buttons); a
// compact card is just the art and play/pause.
Panel {
  id: root

  readonly property bool hasPlayer: MediaManager.hasActivePlayer
  readonly property string artSource: MediaManager.artSource
  // Card only: the art beside the info and controls, when the slot is
  // clearly wider than tall
  readonly property bool sideBySide: root.embedded && root.innerWidth >= root.innerHeight * 1.25
  // Card stacked: the art centred, the track centred beneath it
  readonly property bool stacked: root.embedded && !root.sideBySide
  // A short wide slot: title, artist and a slim transport only
  readonly property bool short: root.sideBySide && root.height < Appearance.fontSize * 13
  // A tall wide slot (a big lock screen or page card): larger text and
  // controls, centred beside the art
  readonly property bool large: root.sideBySide && root.innerHeight >= Appearance.fontSize * 20
  // A strip: one row of small art, the track and the buttons
  readonly property bool mini: root.embedded && !root.compact && root.height < Appearance.fontSize * 7
  readonly property real artSize: Widget.px(96)
  // The blurred cover shows: every line over it takes the veil's ink
  readonly property bool washed: root.hasPlayer && root.artSource !== "" && root.properties.showCoverBlur
  // A seek bar is being dragged, so the popout mustn't dismiss
  property bool seeking: false

  Component.onCompleted: MediaManager.acquire(root)
  Component.onDestruction: MediaManager.release(root)

  hovered: pointerInside || root.seeking
  // The blurred cover is a box of its own, so bare it keeps its padding
  drawsBox: true

  fullMinWidth: Appearance.fontSize * 10
  fullMinHeight: Appearance.fontSize * 3.5

  spacing: Widget.spacing
  implicitWidth: Widget.textPx(380)

  component MediaButton: StyledIconButton {
    id: button
    property bool primary: false
    kind: button.primary ? "primary" : "text"
    borderRadius: button.size / 2
    iconSize: Math.round(button.size * 0.5)
  }

  // The cover (CoverArt)
  component Art: CoverArt {
    source: root.artSource
  }

  // Title, artist and album; the player's name above, click to cycle
  // players when there are several
  component TrackInfo: ColumnLayout {
    spacing: 2
    Item {
      visible: !root.short
      Layout.fillWidth: true
      implicitHeight: playerRow.implicitHeight
      RowLayout {
        id: playerRow
        anchors.fill: parent
        spacing: Widget.spacing
        Item {
          visible: root.stacked
          Layout.fillWidth: true
        }
        StyledLabel {
          Layout.fillWidth: true
          Layout.maximumWidth: Math.ceil(implicitWidth)
          overflow: "line"
          text: MediaManager.identity
          role: "caption"
          tone: root.washed ? "text" : "faint"
        }
        StyledIcon {
          visible: MediaManager.players.length > 1
          text: "refresh"
          size: "xs"
          tone: root.washed ? "text" : "faint"
        }
        Item {
          Layout.fillWidth: true
        }
      }
      MouseArea {
        anchors.fill: parent
        enabled: MediaManager.players.length > 1
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          const players = MediaManager.players;
          MediaManager.selectPlayer(players[(players.indexOf(MediaManager.activePlayer) + 1) % players.length]);
        }
      }
    }
    Item {
      Layout.fillHeight: true
    }
    CrossFade {
      Layout.fillWidth: true
      value: MediaManager.trackTitle || I18n.tr("Unknown track")
      delegate: StyledText {
        required property var value
        overflow: "line"
        horizontalAlignment: root.stacked ? Text.AlignHCenter : Text.AlignLeft
        text: value
        role: root.large ? "headline" : root.short ? "label" : "title"
        tone: root.washed ? "text" : "accent"
        font.weight: Style.weightStrong
      }
    }
    CrossFade {
      Layout.fillWidth: true
      // Kept as a line when empty, so the popout's height never changes
      value: MediaManager.trackArtist || " "
      delegate: StyledText {
        required property var value
        overflow: "line"
        horizontalAlignment: root.stacked ? Text.AlignHCenter : Text.AlignLeft
        text: value
        role: root.large ? "title" : root.short ? "caption" : "body"
        tone: root.washed ? "text" : "muted"
      }
    }
    CrossFade {
      visible: !root.short
      Layout.fillWidth: true
      // MediaManager doesn't surface the album, but the Mpris player does
      value: (MediaManager.activePlayer?.trackAlbum ?? "") || " "
      delegate: StyledText {
        required property var value
        overflow: "line"
        horizontalAlignment: root.stacked ? Text.AlignHCenter : Text.AlignLeft
        text: value
        role: root.large ? "body" : "caption"
        tone: root.washed ? "text" : "faint"
      }
    }
  }

  // Seek bar with times, then previous / play-pause / next
  component Transport: ColumnLayout {
    spacing: Widget.spacing / 2
    StyledSlider {
      id: seek
      Layout.fillWidth: true
      Layout.preferredHeight: Widget.px(root.short ? 10 : root.large ? 20 : 16)
      enabled: MediaManager.canSeek
      troughHeight: Widget.px(root.short ? 4 : root.large ? 8 : 6)
      handleSize: Widget.px(root.short ? 10 : root.large ? 18 : 14)
      value: Math.min(1, Math.max(0, MediaManager.progress))
      onPressedChanged: root.seeking = pressed
      onReleased: value => MediaManager.setPositionByRatio(value)
    }
    RowLayout {
      visible: !root.short
      Layout.fillWidth: true
      StyledLabel {
        text: MediaManager.formatTime(seek.pressed ? seek.position * MediaManager.length : MediaManager.position)
        role: root.large ? "caption" : "micro"
        tone: root.washed ? "text" : "faint"
      }
      Item {
        Layout.fillWidth: true
      }
      StyledLabel {
        text: MediaManager.formatTime(MediaManager.length)
        role: root.large ? "caption" : "micro"
        tone: root.washed ? "text" : "faint"
      }
    }
    RowLayout {
      Layout.alignment: Qt.AlignHCenter
      spacing: root.short ? Widget.spacing : Widget.spacing * 1.5
      MediaButton {
        size: Widget.height * (root.large ? 1.4 : 1)
        iconText: "skip_previous"
        enabled: MediaManager.canGoPrevious
        onClicked: MediaManager.previous() // allowed: on the lock screen too, where x-lockActions cover MediaManager's transport
      }
      MediaButton {
        primary: true
        size: Widget.height * (root.short ? 1.2 : root.large ? 2 : 1.4)
        iconText: MediaManager.isPlaying ? "pause" : "play_arrow"
        enabled: MediaManager.canTogglePlaying
        onClicked: MediaManager.togglePlayPause() // allowed: on the lock screen too, where x-lockActions cover MediaManager's transport
      }
      MediaButton {
        size: Widget.height * (root.large ? 1.4 : 1)
        iconText: "skip_next"
        enabled: MediaManager.canGoNext
        onClicked: MediaManager.next() // allowed: on the lock screen too, where x-lockActions cover MediaManager's transport
      }
    }
  }

  // The cover blurred, rounded to the box and tinted with the theme's
  // background, so text reads on it in light and dark themes alike
  background: Item {
    visible: root.washed
    ClippingRectangle {
      anchors.fill: parent
      anchors.margins: root.embedded ? Appearance.borderWidth : 0
      radius: Math.max(0, root.boxRadius - (root.embedded ? Appearance.borderWidth : 0))
      color: "transparent"
      // Larger than the box, so the blur doesn't fade out at its edges
      CrossFade {
        anchors.fill: parent
        anchors.margins: -Widget.px(48)
        value: root.artSource
        delegate: Image {
          required property var value
          readonly property bool ready: status !== Image.Loading
          source: value
          // blurred to a wash, so a small decode does
          sourceSize: Qt.size(128, 128)
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          layer.enabled: true // style-exempt: no text
          layer.effect: MultiEffect { // style-exempt: no text
            blurEnabled: true
            blur: 1
            blurMax: 48
            saturation: 0.2
          }
        }
      }
      Rectangle {
        anchors.fill: parent
        color: Style.veil
      }
    }
  }

  // Compact: the art with play/pause over it
  compactContent: Item {
    Art {
      anchors.fill: parent
    }
    MediaButton {
      anchors.centerIn: parent
      visible: root.hasPlayer
      primary: true
      size: Math.min(parent.width, parent.height) * 0.4
      iconText: MediaManager.isPlaying ? "pause" : "play_arrow"
      enabled: MediaManager.canTogglePlaying
      onClicked: MediaManager.togglePlayPause() // allowed: on the lock screen too, where x-lockActions cover MediaManager's transport
    }
  }

  // --- No player ---
  Item {
    visible: !root.hasPlayer
    Layout.fillWidth: true
    Layout.fillHeight: root.embedded
    Layout.preferredHeight: root.embedded ? -1 : root.artSize
    EmptyState {
      anchors.centerIn: parent
      maxWidth: parent.width
      availableHeight: root.embedded ? parent.height : -1
      icon: "music_note"
      text: I18n.tr("Nothing playing")
    }
  }

  // --- A strip: art, track and buttons in a row ---
  Loader {
    active: root.hasPlayer && root.mini
    visible: active
    Layout.fillWidth: true
    Layout.fillHeight: true

    sourceComponent: RowLayout {
      spacing: Widget.spacing
      // Room for previous and next beside play/pause
      readonly property bool wide: root.width >= Appearance.fontSize * 22

      Art {
        readonly property real side: root.innerHeight
        visible: side >= 24
        Layout.preferredWidth: side
        Layout.preferredHeight: side
      }
      // The track opens the whole player over the grid
      ColumnLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 0
        TapHandler {
          enabled: root.canExpand("NowPlaying")
          onTapped: root.expand("NowPlaying", root.properties)
        }
        HoverHandler {
          enabled: root.canExpand("NowPlaying")
          cursorShape: Qt.PointingHandCursor
        }
        CrossFade {
          Layout.fillWidth: true
          value: MediaManager.trackTitle || I18n.tr("Unknown track")
          delegate: StyledText {
            required property var value
            overflow: "line"
            text: value
            tone: root.washed ? "text" : "accent"
            font.weight: Style.weightStrong
          }
        }
        CrossFade {
          visible: root.innerHeight >= Appearance.fontSize * 2.6
          Layout.fillWidth: true
          value: MediaManager.trackArtist
          delegate: StyledText {
            required property var value
            overflow: "line"
            text: value
            role: "caption"
            tone: root.washed ? "text" : "muted"
          }
        }
      }
      MediaButton {
        visible: parent.wide && root.properties.showControls
        size: Math.min(Widget.height, root.innerHeight)
        iconText: "skip_previous"
        enabled: MediaManager.canGoPrevious
        onClicked: MediaManager.previous() // allowed: on the lock screen too, where x-lockActions cover MediaManager's transport
      }
      MediaButton {
        visible: root.properties.showControls
        primary: true
        size: Math.min(Widget.height * 1.2, root.innerHeight)
        iconText: MediaManager.isPlaying ? "pause" : "play_arrow"
        enabled: MediaManager.canTogglePlaying
        onClicked: MediaManager.togglePlayPause() // allowed: on the lock screen too, where x-lockActions cover MediaManager's transport
      }
      MediaButton {
        visible: parent.wide && root.properties.showControls
        size: Math.min(Widget.height, root.innerHeight)
        iconText: "skip_next"
        enabled: MediaManager.canGoNext
        onClicked: MediaManager.next() // allowed: on the lock screen too, where x-lockActions cover MediaManager's transport
      }
    }
  }

  // --- Art and info (and, wide, the controls) ---
  Loader {
    active: root.hasPlayer && !root.mini
    visible: active
    Layout.fillWidth: true
    Layout.fillHeight: root.embedded

    sourceComponent: GridLayout {
      columns: root.stacked ? 1 : 2
      columnSpacing: root.embedded ? root.pad : Widget.spacing * 1.5
      rowSpacing: Widget.spacing

      Art {
        // From the card's size, not the grid's: that depends on this
        // Beside the info, never over 40% of the width, so the text keeps room;
        // stacked, whatever height the info and controls leave (a small card
        // would otherwise push them out of the box)
        readonly property real side: !root.embedded ? root.artSize : root.sideBySide ? Math.min(root.innerHeight, root.innerWidth * 0.4) : Math.max(0, Math.min(root.innerWidth, root.innerHeight * 0.5, root.innerHeight - details.implicitHeight - Widget.spacing))
        visible: side >= 32
        Layout.preferredWidth: side
        Layout.preferredHeight: side
        Layout.alignment: root.stacked ? Qt.AlignHCenter : root.sideBySide ? Qt.AlignVCenter : Qt.AlignTop
      }

      ColumnLayout {
        id: details
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumWidth: 0
        spacing: root.short ? 2 : Widget.spacing
        // Large: the track and controls centred, not spread down the side
        Item {
          visible: root.large
          Layout.fillHeight: true
        }
        TrackInfo {
          Layout.fillWidth: true
          Layout.fillHeight: !root.large
        }
        Loader {
          active: root.embedded && root.properties.showControls
          visible: active
          Layout.fillWidth: true
          Layout.topMargin: root.large ? Widget.spacing : 0
          sourceComponent: Transport {}
        }
        Item {
          visible: root.large
          Layout.fillHeight: true
        }
      }
    }
  }

  // --- Popout: the controls beneath ---
  Loader {
    active: root.hasPlayer && !root.embedded && root.properties.showControls
    visible: active
    Layout.fillWidth: true
    sourceComponent: Transport {}
  }
}
