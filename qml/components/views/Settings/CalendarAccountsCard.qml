pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.ui
import qs.services.apps
import qs.components.forms
import qs.components.methods
import qs.components.reusable

// The Calendar section's first card (its `x-card`): the accounts as tabs,
// one shown at a time: its address and username, its password (to the
// keyring, or the secrets file without one: never the settings draft or
// config.json), Connect, which finds its calendars, and the calendars, each
// shown or hidden, with its color and the one new events go to. A local
// account ("On this computer") has no server: Add calendar makes one, named
// and removed here (removing leaves its folder of events on disk). Account
// and calendar edits go through the settings draft like any other row.
FoldingCard {
  id: root

  // The settings group key it folds under, from SettingsContent
  property string foldKey

  readonly property var accountSchema: ConfigManager.configSchema.definitions.CalendarAccount
  readonly property var accounts: CalendarConfig.savedAccounts
  readonly property string defaultCalendar: CalendarConfig.defaultCalendar
  property int selected: 0
  readonly property int current: Math.max(0, Math.min(root.selected, root.accounts.length - 1))
  readonly property var account: root.accounts[root.current] ?? null
  readonly property string accountId: root.account?.id ?? ""
  readonly property bool isLocal: root.account?.kind === "local"
  readonly property string passwordStatus: root.accountId ? SecretsManager.secretStatus("calendar", root.accountId) : ""

  // Connect's state: { busy, ok, text }
  property var result: null
  // Removing an account or a local calendar asks for a second click
  ConfirmGate {
    id: gate
    timeout: 0
  }
  // False once destroyed, for callbacks that outlive the card
  property bool _alive: true
  Component.onDestruction: root._alive = false

  collapsed: SettingsManager.isCollapsed(root.foldKey)
  onToggled: SettingsManager.setCollapsed(root.foldKey, !root.collapsed)
  onCurrentChanged: {
    root.result = null;
    gate.disarm();
    // A password typed for one account is never saved to another
    passwordField.text = "";
  }

  // Passwords may have changed outside the shell (secret-tool, the file)
  Component.onCompleted: SecretsManager.refreshSecrets("calendar", CalendarConfig.accounts.map(account => account.id))

  function _commit(accounts) {
    SettingsManager.setValue(["Calendar", "items"], accounts);
  }

  // Merges `values` into the shown account
  function edit(values) {
    const accounts = Utils.clone(root.accounts);
    Object.assign(accounts[root.current], values);
    root._commit(accounts);
  }

  function add() {
    const accounts = Utils.clone(root.accounts);
    accounts.push(SchemaValidation.applyDefaults({
      "id": Utils.freeId("account", accounts.map(account => account.id).concat(CalendarConfig.savedPasswordIds))
    }, root.accountSchema, ConfigManager.configSchema));
    root._commit(accounts);
    root.selected = accounts.length - 1;
  }

  function remove() {
    if (!gate.pass("account", true))
      return;
    const accounts = Utils.clone(root.accounts);
    accounts.splice(root.current, 1);
    root._commit(accounts);
    root.selected = Math.max(0, root.current - 1);
  }

  // A provider's address, filled in when it's picked over an empty one or
  // another provider's
  readonly property var presetUrls: ({
      "icloud": "https://caldav.icloud.com",
      "fastmail": "https://caldav.fastmail.com",
      "nextcloud": ""
    })
  function _edited(path, value) {
    const values = {
      [path[0]]: value
    };
    if (path[0] === "preset") {
      const url = root.account.url ?? "";
      if (url === "" || Object.values(root.presetUrls).includes(url))
        values.url = root.presetUrls[value] ?? url;
    }
    root.edit(values);
  }

  // Finds the account's calendars and merges them in: new ones holding
  // events come in shown; ones the server no longer lists go
  function connect() {
    const account = root.account;
    const index = root.current;
    root.result = {
      "busy": true,
      "ok": false,
      "text": ""
    };
    CalendarManager.discover(account, result => {
      if (!root || !root._alive)
        return;
      if (!result.ok) {
        root.result = {
          "busy": false,
          "ok": false,
          "text": CalendarManager.errorText(result)
        };
        return;
      }
      const accounts = Utils.clone(root.accounts);
      const old = accounts[index]?.calendars ?? [];
      if (!accounts[index])
        return;
      // What the server says of them is the calendar cache's; the config
      // keeps what the user set
      CalendarManager.remember(account.id, result.calendars);
      accounts[index].calendars = result.calendars.map(found => {
        const known = old.find(calendar => calendar.href === found.href);
        return {
          "href": found.href,
          "name": known?.name ?? "",
          "color": known?.color ?? "",
          "enabled": known?.enabled ?? found.components.includes("VEVENT")
        };
      });
      root._commit(accounts);
      const events = result.calendars.filter(calendar => calendar.components.includes("VEVENT")).length;
      root.result = {
        "busy": false,
        "ok": true,
        "text": I18n.tr("Found {0} calendars", events)
      };
    });
  }

  // A new local calendar: its href is the folder its events go in, never
  // one a removed calendar left behind
  function addLocal() {
    const accounts = Utils.clone(root.accounts);
    const calendars = accounts[root.current].calendars ?? [];
    calendars.push({
      "href": root.accountId + "-" + Date.now().toString(36),
      "name": I18n.tr("Calendar {0}", calendars.length + 1),
      "color": "",
      "enabled": true
    });
    accounts[root.current].calendars = calendars;
    root._commit(accounts);
  }

  // Removes a local calendar on a second click; its folder stays
  function dropLocal(href) {
    if (!gate.pass("calendar:" + href, true))
      return;
    const accounts = Utils.clone(root.accounts);
    accounts[root.current].calendars = accounts[root.current].calendars.filter(calendar => calendar.href !== href);
    root._commit(accounts);
  }

  function setCalendar(href, values) {
    const accounts = Utils.clone(root.accounts);
    const calendar = accounts[root.current]?.calendars.find(c => c.href === href);
    if (!calendar)
      return;
    Object.assign(calendar, values);
    root._commit(accounts);
  }

  headerExtras: StyledTextButton {
    iconText: "add"
    text: I18n.tr("Add")
    onClicked: root.add()
  }

  StyledText {
    visible: root.accounts.length === 0
    Layout.fillWidth: true
    text: I18n.tr("No accounts yet. Add one for a CalDAV server (iCloud, Fastmail, Nextcloud, …), an .ics subscription, or calendars kept on this computer.")
    tone: "muted"
    overflow: "wrap"
  }

  // One tab per account
  SegmentTabs {
    visible: root.accounts.length > 0
    Layout.fillWidth: true
    count: root.accounts.length
    current: root.current
    labelAt: i => {
      const entry = root.accounts[i];
      return entry.name || entry.username || CalendarConfig.hostOf(entry.url) || (entry.kind === "local" ? I18n.tr("This computer") : I18n.tr("Account {0}", i + 1));
    }
    onPicked: i => root.selected = i
  }

  SchemaPropertiesForm {
    visible: root.account !== null
    Layout.fillWidth: true
    propertiesSchema: root.accountSchema.properties
    order: root.accountSchema["x-order"] ?? []
    values: root.account ?? ({})
    onEdited: (path, value) => root._edited(path, value)
  }

  StyledText {
    visible: root.account?.kind === "caldav" && root.account?.preset === "icloud"
    Layout.fillWidth: true
    text: I18n.tr("iCloud needs an app-specific password: make one at account.apple.com (Sign-In and Security → App-Specific Passwords). Your username is your Apple Account's email.")
    role: "caption"
    overflow: "wrap"
  }

  // The password, never in the draft
  RowLayout {
    visible: root.account?.kind === "caldav"
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    StyledLabel {
      text: I18n.tr("Password")
    }
    SubmitEntry {
      id: passwordField
      secret: true
      placeholderText: root.passwordStatus === "keyring" || root.passwordStatus === "file" ? I18n.tr("Type a new one to replace it") : I18n.tr("The account's password")
      buttonText: I18n.tr("Save")
      onSubmitted: {
        SecretsManager.setSecret("calendar", root.accountId, I18n.tr("{0} calendar", root.account.name || CalendarConfig.hostOf(root.account.url)), passwordField.text);
        passwordField.text = "";
      }
    }
    SecretStatusChip {
      status: root.passwordStatus
      missingText: I18n.tr("No password")
    }
  }

  RowLayout {
    visible: root.account !== null
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    StyledText {
      Layout.fillWidth: true
      text: root.isLocal ? I18n.tr("Kept in {0}", Paths.userDataPath + "calendars") : root.result?.busy ? I18n.tr("Connecting…") : root.result?.text ?? ""
      tone: root.isLocal || root.result?.busy ? "faint" : root.result?.ok ? "success" : "error"
      role: "caption"
      overflow: "wrap"
    }
    StyledTextButton {
      visible: root.isLocal
      iconText: "add"
      text: I18n.tr("Add calendar")
      onClicked: root.addLocal()
    }
    StyledTextButton {
      visible: !root.isLocal
      enabled: !root.result?.busy && (root.account?.url ?? "") !== ""
      iconText: "sync"
      text: (root.account?.calendars ?? []).length > 0 ? I18n.tr("Refresh calendars") : I18n.tr("Connect")
      onClicked: root.connect()
    }
    StyledTextButton {
      iconText: "delete"
      text: gate.armed === "account" ? I18n.tr("Click again to remove") : I18n.tr("Remove")
      kind: "danger"
      onClicked: root.remove()
    }
  }

  // The account's calendars
  Repeater {
    model: (root.account?.calendars ?? []).length

    delegate: FormRow {
      id: calendarRow
      required property int index
      readonly property var calendar: root.account.calendars[index] ?? ({})
      readonly property string calendarId: root.accountId + "|" + calendarRow.calendar.href
      // The calendar as CalendarManager joins it with what its server said
      readonly property var joined: CalendarManager.calendar(calendarRow.calendarId)
      readonly property bool holdsEvents: calendarRow.joined?.events ?? true

      // Lists without events (iCloud's reminders) wait for to-dos
      shown: calendarRow.holdsEvents
      bodyHeight: line.implicitHeight

      RowLayout {
        id: line
        width: parent.width
        spacing: Widget.spacing

        StyledSwitch {
          checked: calendarRow.calendar.enabled ?? false
          onToggled: root.setCalendar(calendarRow.calendar.href, {
            "enabled": checked
          })
        }
        Rectangle {
          Layout.preferredWidth: Appearance.fontSize * 0.8
          Layout.preferredHeight: width
          radius: width / 2
          color: Style.resolve(calendarRow.joined?.color ?? "accent")
        }
        StyledLabel {
          visible: !root.isLocal
          Layout.fillWidth: true
          text: calendarRow.joined?.name || calendarRow.calendar.href
          textFormat: Text.PlainText
          overflow: "line"
        }
        // A local calendar's name is the user's to change, committed like
        // every settings text field: on Enter, focus loss or the page's Save
        // (CommitEntry). An empty name puts the saved one back; the row
        // showing another calendar (one above it removed) drops a commit
        CommitEntry {
          id: nameField
          visible: root.isLocal
          Layout.fillWidth: true
          placeholderText: I18n.tr("Name")
          // One line, cut off rather than wrapped in a narrow field
          input.wrapMode: TextInput.NoWrap
          value: calendarRow.calendar.name ?? ""
          scope: calendarRow.calendar.href
          onCommitted: text => {
            const name = text.trim();
            if (name !== "" && name !== nameField.value)
              root.setCalendar(calendarRow.calendar.href, {
                "name": name
              });
            else
              nameField.discardTyped();
          }
        }
        StatusChip {
          shown: calendarRow.joined?.readOnly ?? false
          tone: "neutral"
          text: I18n.tr("Read-only")
        }
        ToggleChip {
          visible: calendarRow.joined?.writable ?? false
          text: I18n.tr("Default")
          checked: root.defaultCalendar === calendarRow.calendarId
          onToggled: SettingsManager.setValue(["Calendar", "defaultCalendar"], checked ? "" : calendarRow.calendarId)
        }
        // The color picker every color setting uses, its rows in their colors
        SchemaComboBox {
          Layout.fillWidth: false
          Layout.preferredWidth: Appearance.fontSize * 11
          label: ""
          options: [""].concat(Theme.baseColorNames)
          optionLabels: ({
              "": root.isLocal ? I18n.tr("Accent") : I18n.tr("Server color")
            })
          swatches: true
          currentValue: calendarRow.calendar.color ?? ""
          onSelectionChanged: value => root.setCalendar(calendarRow.calendar.href, {
              "color": value
            })
        }
        StyledTextButton {
          visible: root.isLocal
          iconText: "delete"
          text: gate.armed === "calendar:" + calendarRow.calendar.href ? I18n.tr("Click again to remove (its files stay)") : ""
          kind: "danger"
          tooltipText: gate.armed === "calendar:" + calendarRow.calendar.href ? "" : I18n.tr("Remove this calendar")
          onClicked: root.dropLocal(calendarRow.calendar.href)
        }
      }
    }
  }

  StyledText {
    visible: CalendarManager.calendars.some(calendar => calendar.account === root.accountId && !calendar.events)
    Layout.fillWidth: true
    text: I18n.tr("Task lists (such as iCloud's reminders) aren't shown yet.")
    tone: "muted"
    role: "caption"
    overflow: "wrap"
  }
}
