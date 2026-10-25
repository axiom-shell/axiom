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
  readonly property var accounts: SettingsManager.localConfig?.Calendar?.accounts ?? CalendarConfig.savedAccounts
  readonly property string defaultCalendar: SettingsManager.localConfig?.Calendar?.defaultCalendar ?? CalendarConfig.defaultCalendar
  property int selected: 0
  readonly property int current: Math.max(0, Math.min(root.selected, root.accounts.length - 1))
  readonly property var account: root.accounts[root.current] ?? null
  // The shown account's id as the reader fills it in (numbered when empty)
  readonly property string accountId: root.account ? (root.account.id || "account-" + (root.current + 1)) : ""
  readonly property bool isLocal: root.account?.kind === "local"
  readonly property string passwordStatus: root.accountId ? SecretsManager.secretStatus("calendar", root.accountId) : ""

  // Connect's state: { busy, ok, text }
  property var result: null
  property bool confirmRemove: false
  // The local calendar a second click removes ("" for none)
  property string confirmDrop: ""
  // False once destroyed, for callbacks that outlive the card
  property bool _alive: true
  Component.onDestruction: root._alive = false

  description: CalendarManager.missingModule ? CalendarManager.missingText(CalendarManager.missingModule) : CalendarManager.available ? "" : I18n.tr("The calendar helper couldn't run (it needs python3).")
  collapsed: SettingsManager.isCollapsed(root.foldKey)
  onToggled: SettingsManager.setCollapsed(root.foldKey, !root.collapsed)
  onCurrentChanged: {
    root.result = null;
    root.confirmRemove = false;
    root.confirmDrop = "";
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
      "id": Utils.freeId("account", accounts.map((account, index) => account.id || "account-" + (index + 1)))
    }, root.accountSchema, ConfigManager.configSchema));
    root._commit(accounts);
    root.selected = accounts.length - 1;
  }

  function remove() {
    if (!root.confirmRemove) {
      root.confirmRemove = true;
      return;
    }
    SecretsManager.clearSecret("calendar", root.accountId);
    const accounts = Utils.clone(root.accounts);
    accounts.splice(root.current, 1);
    root._commit(accounts);
    root.selected = Math.max(0, root.current - 1);
    root.confirmRemove = false;
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
    const account = Object.assign({}, root.account, {
      "id": root.accountId
    });
    const index = root.current;
    root.result = {
      "busy": true,
      "ok": false,
      "text": ""
    };
    CalendarManager.discover(account, null, result => {
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
      accounts[index].id = account.id;
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
    accounts[root.current].id = root.accountId;
    accounts[root.current].calendars = calendars;
    root._commit(accounts);
  }

  // Removes a local calendar on a second click; its folder stays
  function dropLocal(href) {
    if (root.confirmDrop !== href) {
      root.confirmDrop = href;
      return;
    }
    const accounts = Utils.clone(root.accounts);
    accounts[root.current].calendars = accounts[root.current].calendars.filter(calendar => calendar.href !== href);
    root._commit(accounts);
    root.confirmDrop = "";
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
    implicitHeight: Widget.height - Widget.px(4)
    iconText: "add"
    text: I18n.tr("Add")
    onClicked: root.add()
  }

  StyledText {
    visible: root.accounts.length === 0
    Layout.fillWidth: true
    text: I18n.tr("No accounts yet. Add one for a CalDAV server (iCloud, Fastmail, Nextcloud, …), an .ics subscription, or calendars kept on this computer.")
    textColor: Theme.foregroundAlt
    wrapMode: Text.WordWrap
  }

  // One tab per account
  Flow {
    visible: root.accounts.length > 0
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    Repeater {
      model: root.accounts.length

      delegate: SegmentButton {
        id: tab
        required property int index
        readonly property var entry: root.accounts[tab.index]

        implicitHeight: Widget.height - Widget.px(4)
        text: tab.entry.name || tab.entry.username || CalendarConfig.hostOf(tab.entry.url) || (tab.entry.kind === "local" ? I18n.tr("This computer") : I18n.tr("Account {0}", tab.index + 1))
        active: tab.index === root.current
        onClicked: root.selected = tab.index
      }
    }
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
    textColor: Theme.foregroundAlt
    textSize: Appearance.fontSizeBy(-2)
    wrapMode: Text.WordWrap
  }

  // The password, never in the draft
  RowLayout {
    visible: root.account?.kind === "caldav"
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    StyledText {
      text: I18n.tr("Password")
    }
    StyledTextEntry {
      id: passwordField
      Layout.fillWidth: true
      Layout.preferredHeight: Widget.height
      placeholderText: root.passwordStatus === "keyring" || root.passwordStatus === "file" ? I18n.tr("Type a new one to replace it") : I18n.tr("The account's password")
      input.echoMode: TextInput.Password
      onAccepted: savePassword.clicked()
    }
    StyledTextButton {
      id: savePassword
      implicitHeight: Widget.height
      visible: passwordField.text !== ""
      text: I18n.tr("Save")
      backgroundColor: Theme.accent
      textColor: Theme.background
      onClicked: {
        SecretsManager.setSecret("calendar", root.accountId, I18n.tr("{0} calendar", root.account.name || CalendarConfig.hostOf(root.account.url)), passwordField.text);
        passwordField.text = "";
      }
    }
    StatusChip {
      color: root.passwordStatus === "keyring" || root.passwordStatus === "file" ? Theme.success : root.passwordStatus === "none" ? Theme.warning : Theme.foregroundAlt
      text: root.passwordStatus === "keyring" ? I18n.tr("In keyring") : root.passwordStatus === "file" ? I18n.tr("In secrets file") : root.passwordStatus === "none" ? I18n.tr("No password") : I18n.tr("Checking…")
    }
  }

  RowLayout {
    visible: root.account !== null
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    StyledText {
      Layout.fillWidth: true
      text: root.isLocal ? I18n.tr("Kept in {0}", Paths.userDataPath + "calendars") : root.result?.busy ? I18n.tr("Connecting…") : root.result?.text ?? ""
      textColor: root.isLocal || root.result?.busy ? Theme.foregroundAlt : root.result?.ok ? Theme.success : Theme.error
      textSize: Appearance.fontSizeBy(-2)
      wrapMode: Text.Wrap
    }
    StyledTextButton {
      implicitHeight: Widget.height - Widget.px(4)
      visible: root.isLocal
      iconText: "add"
      text: I18n.tr("Add calendar")
      onClicked: root.addLocal()
    }
    StyledTextButton {
      implicitHeight: Widget.height - Widget.px(4)
      visible: !root.isLocal
      enabled: !root.result?.busy && (root.account?.url ?? "") !== ""
      iconText: "sync"
      text: (root.account?.calendars ?? []).length > 0 ? I18n.tr("Refresh calendars") : I18n.tr("Connect")
      onClicked: root.connect()
    }
    StyledTextButton {
      implicitHeight: Widget.height - Widget.px(4)
      iconText: "delete"
      text: root.confirmRemove ? I18n.tr("Click again to remove") : I18n.tr("Remove")
      hoverColor: Theme.error
      onClicked: root.remove()
    }
  }

  // The account's calendars
  StyledSeparator {
    separatorColor: Theme.accent
    visible: (root.account?.calendars ?? []).length > 0
    Layout.fillWidth: true
  }

  Repeater {
    model: (root.account?.calendars ?? []).length

    delegate: RowLayout {
      id: calendarRow
      required property int index
      readonly property var calendar: root.account.calendars[index] ?? ({})
      readonly property string calendarId: root.accountId + "|" + calendarRow.calendar.href
      // The calendar as CalendarManager joins it with what its server said
      readonly property var joined: CalendarManager.calendar(calendarRow.calendarId)
      readonly property bool holdsEvents: calendarRow.joined?.events ?? true

      // Lists without events (iCloud's reminders) wait for to-dos
      visible: calendarRow.holdsEvents
      Layout.fillWidth: true
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
        color: calendarRow.joined?.color ?? Theme.accent
      }
      StyledText {
        visible: !root.isLocal
        Layout.fillWidth: true
        text: calendarRow.joined?.name || calendarRow.calendar.href
        textFormat: Text.PlainText
        elide: Text.ElideRight
      }
      // A local calendar's name is the user's to change, committed like
      // every settings text field: on Enter, focus loss or the page's Save
      // (EditsManager.holdTyping shows Save while typed). Pushed in (the
      // row shows another calendar when one above it is removed), never
      // while being typed in
      StyledTextEntry {
        id: nameField
        readonly property string saved: calendarRow.calendar.name ?? ""
        visible: root.isLocal
        Layout.fillWidth: true
        Layout.preferredHeight: Widget.height - Widget.px(6)
        placeholderText: I18n.tr("Name")
        // One line, cut off rather than wrapped in a narrow field
        input.wrapMode: TextInput.NoWrap
        Component.onCompleted: text = saved
        Component.onDestruction: nameField.commitTyped()
        onSavedChanged: {
          if (!nameField.typed)
            nameField.text = nameField.saved;
        }
        onTextEdited: EditsManager.holdTyping(nameField, nameField.Window.window)
        onAccepted: nameField.commitTyped()
        input.onActiveFocusChanged: {
          if (!nameField.input.activeFocus)
            nameField.commitTyped();
        }

        // The typed name (an empty one puts the saved name back)
        function commitTyped() {
          const name = nameField.text.trim();
          if (nameField.typed && name !== "" && name !== nameField.saved)
            root.setCalendar(calendarRow.calendar.href, {
              "name": name
            });
          nameField.discardTyped();
        }

        function discardTyped() {
          nameField.typed = false;
          nameField.text = nameField.saved;
          EditsManager.releaseTyping(nameField);
        }
      }
      StatusChip {
        shown: calendarRow.calendar.readOnly ?? false
        color: Theme.foregroundAlt
        text: I18n.tr("Read-only")
      }
      SegmentButton {
        visible: !(calendarRow.calendar.readOnly ?? false) && CalendarConfig.writableKind(root.account.kind)
        Layout.fillWidth: false
        implicitHeight: Widget.height - Widget.px(6)
        text: I18n.tr("Default")
        active: root.defaultCalendar === calendarRow.calendarId
        onClicked: SettingsManager.setValue(["Calendar", "defaultCalendar"], active ? "" : calendarRow.calendarId)
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
        implicitHeight: Widget.height - Widget.px(6)
        iconText: "delete"
        text: root.confirmDrop === calendarRow.calendar.href ? I18n.tr("Click again to remove (its files stay)") : ""
        hoverColor: Theme.error
        tooltipText: root.confirmDrop === calendarRow.calendar.href ? "" : I18n.tr("Remove this calendar")
        onClicked: root.dropLocal(calendarRow.calendar.href)
      }
    }
  }

  StyledText {
    visible: (root.account?.calendars ?? []).some(calendar => !(calendar.components ?? []).includes("VEVENT"))
    Layout.fillWidth: true
    text: I18n.tr("Task lists (such as iCloud's reminders) aren't shown yet.")
    opacity: 0.6
    textSize: Appearance.fontSizeBy(-2)
    wrapMode: Text.WordWrap
  }
}
