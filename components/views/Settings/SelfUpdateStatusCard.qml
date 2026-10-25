pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.components.reusable

// The Updates category's first card (the section's `x-card`): the
// installed and newest release, what's new, and Check / Update
FieldGroup {
  id: root

  readonly property string status: {
    if (SelfUpdateManager.applying)
      return "applying";
    if (SelfUpdateManager.checking)
      return "checking";
    if (SelfUpdateManager.error !== "")
      return "error";
    if (SelfUpdateManager.blocked !== "")
      return "blocked";
    return SelfUpdateManager.state;
  }

  readonly property color statusColor: {
    switch (root.status) {
    case "uptodate":
      return Theme.success;
    case "available":
      return Theme.accent;
    case "blocked":
      return Theme.warning;
    case "error":
      return Theme.error;
    }
    return Theme.foregroundAlt;
  }

  readonly property string statusLabel: {
    switch (root.status) {
    case "applying":
      return I18n.tr("Updating…");
    case "checking":
      return I18n.tr("Checking…");
    case "error":
      return I18n.tr("Check failed");
    case "blocked":
      return I18n.tr("Can't update");
    case "uptodate":
      return I18n.tr("Up to date");
    case "available":
      return I18n.tr("Update available");
    }
    if (SelfUpdateManager.lastChecked === 0)
      return I18n.tr("Not checked");
    return SelfUpdateManager.channel === "main" ? I18n.tr("No main branch") : I18n.tr("No releases yet");
  }

  readonly property string installed: {
    const tag = SelfUpdateManager.current;
    const commit = SelfUpdateManager.commit;
    if (tag === "")
      return commit;
    return SelfUpdateManager.ahead ? I18n.tr("{0} + development ({1})", tag, commit) : tag;
  }

  headerExtras: [
    StatusChip {
      text: root.statusLabel
      color: root.statusColor
    }
  ]

  GridLayout {
    Layout.fillWidth: true
    columns: 2
    columnSpacing: Widget.spacing * 2
    rowSpacing: Widget.spacing / 2

    StyledText {
      text: I18n.tr("Installed")
      opacity: 0.7
    }
    StyledText {
      text: root.installed || "—"
      textFamily: "monospace"
      Layout.fillWidth: true
    }

    StyledText {
      text: SelfUpdateManager.channel === "main" ? I18n.tr("Latest on main") : I18n.tr("Latest release")
      opacity: 0.7
    }
    StyledText {
      text: SelfUpdateManager.latest || "—"
      textFamily: "monospace"
      Layout.fillWidth: true
    }

    StyledText {
      text: I18n.tr("Last checked")
      opacity: 0.7
    }
    StyledText {
      text: SelfUpdateManager.lastChecked > 0 ? I18n.formatDate(new Date(SelfUpdateManager.lastChecked), I18n.dateFormat("mediumDate") + " " + I18n.dateFormat("time24")) : I18n.tr("Never")
      Layout.fillWidth: true
    }
  }

  StyledText {
    visible: root.status === "error"
    text: SelfUpdateManager.error
    textColor: Theme.error
    textSize: Appearance.fontSizeBy(-1)
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  StyledText {
    visible: root.status === "blocked"
    text: I18n.tr("{0} is available, but your copy of axiom can't update: {1}", SelfUpdateManager.latest, SelfUpdateManager.blockedReason(SelfUpdateManager.blocked))
    textColor: Theme.warning
    textSize: Appearance.fontSizeBy(-1)
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  // --- What's new ---

  ColumnLayout {
    visible: SelfUpdateManager.notes !== "" && SelfUpdateManager.state === "available"
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    StyledText {
      text: SelfUpdateManager.behind > 0 ? I18n.tr("What's new in {0} ({1} commits)", SelfUpdateManager.latest, SelfUpdateManager.behind) : I18n.tr("What's new in {0}", SelfUpdateManager.latest)
      font.bold: true
      Layout.fillWidth: true
    }

    StyledContainer {
      Layout.fillWidth: true
      implicitHeight: notes.implicitHeight + Widget.padding * 2
      backgroundColor: Theme.background

      StyledText {
        id: notes
        anchors.fill: parent
        anchors.margins: Widget.padding
        text: SelfUpdateManager.notes
        textSize: Appearance.fontSizeBy(-1)
        wrapMode: Text.WordWrap
      }
    }
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    StyledText {
      text: SelfUpdate.mode === "off" ? I18n.tr("Automatic checks are off.") : I18n.tr("Checked at startup and once a day.")
      opacity: 0.6
      textSize: Appearance.fontSizeBy(-2)
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    StyledTextButton {
      implicitHeight: Widget.height - Widget.px(4)
      visible: !SelfUpdateManager.busy
      text: I18n.tr("Check now")
      onClicked: SelfUpdateManager.check()
    }

    StyledTextButton {
      implicitHeight: Widget.height - Widget.px(4)
      visible: SelfUpdateManager.available && !SelfUpdateManager.busy
      text: I18n.tr("Update to {0}", SelfUpdateManager.latest)
      backgroundColor: Theme.accent
      textColor: Theme.background
      onClicked: SelfUpdateManager.apply()
    }
  }
}
