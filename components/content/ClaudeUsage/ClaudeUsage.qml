pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.apps
import qs.components.reusable
import qs.components.content.base

// Claude plan usage per account (from ClaudeUsageManager): the session and
// weekly limits with their reset times, extra usage and where the week went.
// The ClaudeUsage widget's popout; the widget acquires the manager.
Panel {
  id: root

  // [{ label, configDir }], from the widget's config
  property var accounts: []
  property int warnThreshold: 75
  property int criticalThreshold: 90

  // Re-read on every update, so the relative times stay current
  readonly property real now: {
    void ClaudeUsageManager.states;
    return Date.now();
  }
  readonly property var accountRows: accounts.map(a => Object.assign({}, ClaudeUsageManager.stateFor(a.configDir) ?? {
      "status": "pending"
    }, {
      "label": a.label || a.configDir
    }))

  spacing: Widget.padding
  implicitWidth: Math.max(Widget.px(320), body.implicitWidth + margins * 2)

  function duration(ms) {
    const minutes = Math.max(0, Math.round(ms / 60000));
    if (minutes < 60)
      return I18n.tr("{0}m", minutes);
    if (minutes < 1440)
      return I18n.tr("{0}h {1}m", Math.floor(minutes / 60), minutes % 60);
    return I18n.tr("{0}d {1}h", Math.floor(minutes / 1440), Math.floor(minutes % 1440 / 60));
  }
  function resetText(resetsAt) {
    const t = Date.parse(resetsAt);
    return isNaN(t) ? "" : I18n.tr("resets in {0}", duration(t - root.now));
  }
  function colorFor(percent) {
    return percent >= root.criticalThreshold ? Theme.error : percent >= root.warnThreshold ? Theme.warning : Theme.accent;
  }

  component Meter: ColumnLayout {
    id: meter
    required property string title
    property var usage: null

    visible: usage !== null
    spacing: 2
    Layout.fillWidth: true

    RowLayout {
      Layout.fillWidth: true
      StyledText {
        text: meter.title
        Layout.fillWidth: true
        elide: Text.ElideRight
      }
      StyledText {
        text: `${meter.usage?.percent ?? 0}%`
        font.bold: true
      }
    }
    Rectangle {
      Layout.fillWidth: true
      implicitHeight: Widget.px(6)
      radius: height / 2
      color: Theme.backgroundHighlight
      Rectangle {
        width: parent.width * Math.min(1, (meter.usage?.percent ?? 0) / 100)
        height: parent.height
        radius: parent.radius
        color: root.colorFor(meter.usage?.percent ?? 0)
      }
    }
    StyledText {
      visible: text !== ""
      text: root.resetText(meter.usage?.resetsAt ?? "")
      textColor: Theme.foregroundAlt
      textSize: Appearance.fontSizeBy(-2)
    }
  }

  Repeater {
    model: root.accountRows.length

    ColumnLayout {
      id: account
      required property int index
      readonly property var row: root.accountRows[index]

      spacing: Widget.padding
      Layout.fillWidth: true

      StyledSeparator {
        visible: account.index > 0
        Layout.fillWidth: true
        separatorColor: Theme.backgroundHighlight
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Widget.padding

        StyledText {
          text: account.row.label
          font.bold: true
          textColor: Theme.accent
        }
        StyledText {
          text: [account.row.org, account.row.plan].filter(s => s).join(" · ")
          textColor: Theme.foregroundAlt
          textSize: Appearance.fontSizeBy(-2)
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
        StyledText {
          // I18n.tr("token expired") I18n.tr("fetch failed") I18n.tr("not logged in") I18n.tr("loading…")
          readonly property var labels: ({
              "expired": "token expired",
              "error": "fetch failed",
              "missing": "not logged in",
              "pending": "loading…"
            })
          visible: account.row.status !== "ok"
          text: I18n.tr(labels[account.row.status] ?? "loading…")
          textColor: account.row.status === "pending" ? Theme.foregroundAlt : Theme.warning
          textSize: Appearance.fontSizeBy(-2)
        }
      }

      StyledText {
        visible: account.row.status === "expired" || account.row.status === "error" || account.row.status === "missing"
        text: account.row.status === "expired" ? I18n.tr("Run Claude Code with this account to refresh its login.") : (account.row.error ?? "")
        textColor: Theme.foregroundAlt
        textSize: Appearance.fontSizeBy(-2)
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        Layout.maximumWidth: Widget.px(320)
      }

      Meter {
        title: I18n.tr("Current session")
        usage: account.row.session ?? null
      }
      Meter {
        title: I18n.tr("Weekly (all models)")
        usage: account.row.weekly ?? null
      }
      Meter {
        title: I18n.tr("Weekly (Opus)")
        usage: account.row.weeklyOpus ?? null
      }
      Meter {
        title: I18n.tr("Weekly (Sonnet)")
        usage: account.row.weeklySonnet ?? null
      }
      Meter {
        title: I18n.tr("Extra usage")
        usage: account.row.extra ?? null
      }

      StyledText {
        visible: (account.row.breakdown ?? []).length > 0
        text: I18n.tr("This week: {0}", (account.row.breakdown ?? []).map(b => `${b.name} ${b.percent}%`).join(" · "))
        textColor: Theme.foregroundAlt
        textSize: Appearance.fontSizeBy(-2)
        wrapMode: Text.Wrap
        Layout.fillWidth: true
        Layout.maximumWidth: Widget.px(320)
      }

      StyledText {
        visible: (account.row.fetchedAt ?? 0) > 0
        text: I18n.tr("Updated {0} ago", root.duration(root.now - account.row.fetchedAt))
        textColor: Theme.foregroundAlt
        textSize: Appearance.fontSizeBy(-2)
      }
    }
  }

  StyledText {
    visible: root.accountRows.length === 0
    text: I18n.tr("No accounts configured")
    textColor: Theme.foregroundAlt
  }
}
