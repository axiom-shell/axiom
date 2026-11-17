pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.components.reusable
import qs.components.forms

// The top of the axiom updates card (the section's `x-intro`): the
// installed and newest release, what's new, and Check / Update. `status` and
// `statusTone` are the card's header chip
IntroColumn {
  id: root

  readonly property string stage: {
    if (SelfUpdateManager.managed)
      return "managed";
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

  readonly property string statusTone: {
    switch (root.stage) {
    case "uptodate":
      return "success";
    case "available":
      return "accent";
    case "blocked":
      return "warning";
    case "error":
      return "error";
    }
    return "neutral";
  }

  readonly property string status: {
    switch (root.stage) {
    case "managed":
      return I18n.tr("Package manager");
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

  FactGrid {
    visible: !SelfUpdateManager.managed
    facts: [
      {
        label: I18n.tr("Installed"),
        value: root.installed || "—",
        mono: true
      },
      {
        label: SelfUpdateManager.channel === "main" ? I18n.tr("Latest on main") : I18n.tr("Latest release"),
        value: SelfUpdateManager.latest || "—",
        mono: true
      },
      {
        label: I18n.tr("Last checked"),
        value: SelfUpdateManager.lastChecked > 0 ? I18n.formatDate(new Date(SelfUpdateManager.lastChecked), I18n.dateTimeFormat()) : I18n.tr("Never"),
        wrap: true
      }
    ]
  }

  StatusLine {
    visible: root.stage === "managed"
    Layout.fillWidth: true
    text: I18n.tr("This copy of axiom isn't a git clone: its updates come from your package manager.")
    tone: "muted"
    role: "caption"
  }

  StatusLine {
    visible: root.stage === "error"
    text: SelfUpdateManager.error
    tone: "error"
    Layout.fillWidth: true
  }

  StatusLine {
    visible: root.stage === "blocked"
    text: I18n.tr("{0} is available, but your copy of axiom can't update: {1}", SelfUpdateManager.latest, SelfUpdateManager.blockedReason(SelfUpdateManager.blocked))
    tone: "warning"
    Layout.fillWidth: true
  }

  // --- What's new ---

  ColumnLayout {
    visible: SelfUpdateManager.notes !== "" && SelfUpdateManager.state === "available"
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    StyledText {
      overflow: "wrap"
      text: SelfUpdateManager.behind > 0 ? I18n.tr("What's new in {0} ({1} commits)", SelfUpdateManager.latest, SelfUpdateManager.behind) : I18n.tr("What's new in {0}", SelfUpdateManager.latest)
      role: "label"
      Layout.fillWidth: true
    }

    ItemBox {
      StyledText {
        Layout.fillWidth: true
        text: SelfUpdateManager.notes
        role: "body"
        overflow: "wrap"
      }
    }
  }

  StatusLine {
    visible: !SelfUpdateManager.managed
    Layout.fillWidth: true
    text: SelfUpdate.mode === "off" ? I18n.tr("Automatic checks are off.") : I18n.tr("Checked at startup and once a day.")
    tone: "muted"
    role: "caption"

    StyledTextButton {
      visible: !SelfUpdateManager.busy
      text: I18n.tr("Check now")
      onClicked: SelfUpdateManager.check()
    }

    StyledTextButton {
      visible: SelfUpdateManager.available && !SelfUpdateManager.busy
      text: I18n.tr("Update to {0}", SelfUpdateManager.latest)
      kind: "primary"
      onClicked: SelfUpdateManager.apply()
    }
  }
}
