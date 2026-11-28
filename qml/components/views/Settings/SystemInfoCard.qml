pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.services.core
import qs.services.system
import qs.components.methods
import qs.components.reusable
import qs.components.forms

// Settings page, System (the category's first `card`, wide): this machine
// (its name, operating system, hardware and uptime) and this axiom (its
// version and how it's installed), with Copy system info (the bug report's
// lines, nothing personal) and Rename (hostnamed, polkit asks)
PageCard {
  id: root

  readonly property var info: SystemInfoManager.info
  readonly property var report: SystemInfoManager.report
  readonly property string name: root.info.prettyHostname || root.info.hostname || ""
  property bool renaming: false
  property bool copied: false

  // The facts, in reading order; each is a label and its value's key
  // (constant: the values are read per delegate)
  // I18n.tr("Operating system") I18n.tr("Kernel") I18n.tr("Processor")
  // I18n.tr("Graphics") I18n.tr("Memory") I18n.tr("Disk") I18n.tr("Uptime")
  // I18n.tr("Compositor") I18n.tr("Quickshell") I18n.tr("axiom")
  // I18n.tr("Binary") I18n.tr("Installed as")
  readonly property var facts: [
    {
      "key": "os",
      "label": "Operating system"
    },
    {
      "key": "kernel",
      "label": "Kernel"
    },
    {
      "key": "cpu",
      "label": "Processor"
    },
    {
      "key": "gpus",
      "label": "Graphics"
    },
    {
      "key": "memory",
      "label": "Memory"
    },
    {
      "key": "disk",
      "label": "Disk"
    },
    {
      "key": "uptime",
      "label": "Uptime"
    },
    {
      "key": "compositor",
      "label": "Compositor"
    },
    {
      "key": "quickshell",
      "label": "Quickshell"
    },
    {
      "key": "axiom",
      "label": "axiom"
    },
    {
      "key": "binary",
      "label": "Binary"
    },
    {
      "key": "install",
      "label": "Installed as"
    }
  ]

  function uptimeText(seconds) {
    if (seconds <= 0)
      return "";
    const minutes = Math.floor(seconds / 60) % 60;
    const hours = Math.floor(seconds / 3600) % 24;
    const days = Math.floor(seconds / 86400);
    if (days > 0)
      return I18n.tr("{0} d {1} h", days, hours);
    if (hours > 0)
      return I18n.tr("{0} h {1} min", hours, minutes);
    return I18n.tr("{0} min", minutes);
  }

  function installText() {
    switch (SystemInfoManager.installKind) {
    case "package":
      return I18n.tr("Package {0}, updated by your package manager", Paths.packagedVersion);
    case "dev":
      return I18n.tr("Dev tree {0}", Paths.shortenHome(DevManager.tree));
    case "copy":
      return I18n.tr("A copy (not a git clone)");
    }
    return I18n.tr("Git clone, updates itself");
  }

  function valueOf(key) {
    const i = root.info;
    const r = root.report;
    switch (key) {
    case "os":
      return [i.os, i.arch].filter(Boolean).join(" · ");
    case "kernel":
      return i.kernel ?? "";
    case "cpu":
      return i.cores > 0 ? I18n.tr("{0} ({1} threads)", i.cpu || "?", i.cores) : (i.cpu ?? "");
    case "gpus":
      return (i.gpus ?? []).join("\n");
    case "memory":
      return i.memoryTotal > 0 ? Utils.formatBytes(i.memoryTotal) : "";
    case "disk":
      return i.diskTotal > 0 ? I18n.tr("{0} free of {1}", Utils.formatBytes(i.diskFree), Utils.formatBytes(i.diskTotal)) : "";
    case "uptime":
      return root.uptimeText(SystemInfoManager.uptime);
    case "compositor":
      return r.compositor ?? "";
    case "quickshell":
      return r.quickshell ?? "";
    case "axiom":
      return r.axiom ?? "";
    case "binary":
      return r.binary ?? "";
    case "install":
      return SystemInfoManager.loaded ? root.installText() : "";
    }
    return "";
  }

  Component.onCompleted: SystemInfoManager.refresh()

  headerExtras: [
    StatusChip {
      shown: SystemInfoManager.loading
      text: I18n.tr("Reading…")
      tone: "neutral"
    },
    StyledIconButton {
      iconText: "refresh"
      tooltipText: I18n.tr("Read again")
      enabled: !SystemInfoManager.loading
      onClicked: SystemInfoManager.refresh()
    }
  ]

  // -- The machine: its picture, name and operating system --

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.padding

    Item {
      implicitWidth: Widget.px(56)
      implicitHeight: Widget.px(56)

      IconImage {
        id: logo
        anchors.fill: parent
        visible: status === Image.Ready
        source: root.info.logo ? Quickshell.iconPath(root.info.logo, true) : ""
        asynchronous: true
      }

      StyledIcon {
        anchors.centerIn: parent
        visible: !logo.visible
        text: root.info.chassis === "laptop" ? "laptop" : "computer"
        size: "xl"
        tone: "accent"
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing / 2

      StyledLabel {
        visible: !root.renaming
        text: root.name || I18n.tr("This computer")
        role: "headline"
        overflow: "line"
        Layout.fillWidth: true
      }

      RowLayout {
        visible: root.renaming
        Layout.fillWidth: true
        spacing: Widget.spacing

        SubmitEntry {
          id: nameEntry
          placeholderText: I18n.tr("Computer name")
          buttonText: SystemInfoManager.renaming ? I18n.tr("Renaming…") : I18n.tr("Rename")
          canSubmit: !SystemInfoManager.renaming && nameEntry.text.trim() !== ""
          onSubmitted: SystemInfoManager.rename(nameEntry.text, error => {
            if (!error)
              root.renaming = false;
          })
        }

        StyledTextButton {
          text: I18n.tr("Cancel")
          enabled: !SystemInfoManager.renaming
          onClicked: root.renaming = false
        }
      }

      StyledLabel {
        visible: !!root.info.prettyHostname && root.info.hostname && root.info.prettyHostname !== root.info.hostname && !root.renaming
        text: I18n.tr("Hostname {0}", root.info.hostname)
        textFamily: "monospace"
        role: "caption"
      }

      StyledLabel {
        text: root.info.os ?? ""
        tone: "muted"
        overflow: "line"
        Layout.fillWidth: true
      }

      StatusLine {
        visible: SystemInfoManager.renameError !== ""
        text: SystemInfoManager.renameError
        tone: "error"
        Layout.fillWidth: true
      }
    }

    StyledTextButton {
      visible: !root.renaming
      Layout.alignment: Qt.AlignTop
      text: I18n.tr("Rename…")
      iconText: "edit"
      enabled: SystemInfoManager.loaded
      onClicked: {
        nameEntry.text = root.name;
        root.renaming = true;
        nameEntry.input.forceActiveFocus();
      }
    }
  }

  StyledSeparator {
    Layout.fillWidth: true
  }

  // -- The facts, two to a line --

  FactGrid {
    pairsPerLine: root.width > Widget.px(640) ? 2 : 1
    // I18n.tr: the labels are declared above
    facts: root.facts.map(fact => ({
          "label": I18n.tr(fact.label),
          "value": root.valueOf(fact.key) || "—",
          "wrap": true
        }))
  }

  // -- Copying the report --

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    StyledText {
      Layout.fillWidth: true
      text: I18n.tr("Copy system info copies what a bug report asks for: versions, the compositor and the distribution, never your names or paths.")
      role: "caption"
      overflow: "wrap"
    }

    StyledTextButton {
      text: root.copied ? I18n.tr("Copied") : I18n.tr("Copy system info")
      iconText: root.copied ? "check" : "content_copy"
      enabled: SystemInfoManager.loaded
      onClicked: {
        SystemInfoManager.copyReport();
        root.copied = true;
        copiedReset.restart();
      }
    }
  }

  // Puts the button's label back a moment after a copy (one shot)
  Timer {
    id: copiedReset
    interval: 2000 // how long "Copied" shows
    onTriggered: root.copied = false
  }
}
