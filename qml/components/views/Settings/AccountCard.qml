pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services.session
import qs.services.ui
import qs.components.reusable

// Settings page, General (the General section's `x-card`, wide, first):
// the user's account (AccountManager): their picture, names and kind of
// account, and what they change themselves: the picture (also the lock
// and login screens'), their real name, their password, and the
// first-time setup run again
PageCard {
  id: root

  // Which change is open: "" | "name" | "password"
  property string editing: ""
  // The password change's outcome to show ("" none), and whether it's bad
  property string passwordMessage: ""
  property bool passwordFailed: false

  readonly property string shownName: General.displayName !== AccountManager.login ? General.displayName : (AccountManager.realName || AccountManager.login)

  function open(what) {
    root.editing = root.editing === what ? "" : what;
    root.passwordMessage = "";
    if (root.editing === "name") {
      nameEntry.text = AccountManager.realName;
      nameEntry.input.forceActiveFocus();
    } else if (root.editing === "password") {
      currentEntry.input.text = "";
      newEntry.input.text = "";
      againEntry.input.text = "";
      currentEntry.input.forceActiveFocus();
    }
  }

  // What's wrong with the new passwords before asking passwd ("" nothing)
  readonly property string passwordProblem: {
    if (newEntry.input.text === "" || againEntry.input.text === "")
      return "";
    return newEntry.input.text !== againEntry.input.text ? I18n.tr("The new passwords don't match.") : "";
  }

  function changePassword() {
    if (root.passwordProblem !== "" || newEntry.input.text === "" || currentEntry.input.text === "")
      return;
    AccountManager.changePassword(currentEntry.input.text, newEntry.input.text, result => {
      root.passwordFailed = !result.ok;
      root.passwordMessage = result.ok ? I18n.tr("Your password was changed.") : result.message;
      if (result.ok) {
        root.editing = "";
      } else if (result.reason === "wrong") {
        currentEntry.input.text = "";
        currentEntry.shake();
        currentEntry.input.forceActiveFocus();
      } else {
        newEntry.shake();
        newEntry.input.forceActiveFocus();
      }
      currentEntry.input.text = result.ok ? "" : currentEntry.input.text;
      newEntry.input.text = result.ok ? "" : newEntry.input.text;
      againEntry.input.text = result.ok ? "" : againEntry.input.text;
    });
  }

  Component.onCompleted: AccountManager.refresh()

  headerExtras: [
    StyledTextButton {
      text: I18n.tr("Run setup")
      iconText: "waving_hand"
      tooltipText: I18n.tr("Walks through the compositor setup, monitors, apps and keys, workspaces, the look and integrations again.")
      onClicked: {
        ShellManager.closeOverlay();
        OnboardingManager.open();
      }
    }
  ]

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.padding * 1.5

    // --- The picture: a click changes it ---

    Thumbnail {
      id: picture
      Layout.alignment: Qt.AlignVCenter
      Layout.preferredWidth: Widget.px(88)
      Layout.preferredHeight: Widget.px(88)
      round: true
      source: AccountManager.iconUrl
      cache: false
      decodeSize: Qt.size(picture.width * 2, picture.height * 2)
      placeholderIcon: "person"
      border.color: press.hovered ? Style.accent : Style.borderStrong
      border.width: Style.hairline

      Pressable {
        id: press
        enabled: !AccountManager.busy
        onClicked: AccountManager.pickIcon()
      }

      // A band across the lower third with a camera, while hovered
      Surface {
        tone: "raised"
        solid: true
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.round(parent.height * 0.34)
        radius: 0
        outlined: false
        opacity: press.hovered ? 1 : 0
        Glide on opacity {}

        StyledIcon {
          anchors.centerIn: parent
          text: "add_a_photo"
          size: "md"
        }
      }

      LazyLoader {
        active: press.hovered
        StyledToolTip {
          target: picture
          text: I18n.tr("Change picture")
        }
      }
    }

    // --- Names and the kind of account ---

    ColumnLayout {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      spacing: Widget.spacing / 2

      StyledLabel {
        Layout.fillWidth: true
        text: root.shownName
        role: "headline"
      }

      RowLayout {
        spacing: Widget.spacing

        StyledLabel {
          visible: AccountManager.login !== root.shownName
          text: AccountManager.login
          textFamily: "monospace"
          tone: "muted"
        }

        StatusChip {
          shown: AccountManager.loaded
          text: AccountManager.admin ? I18n.tr("Administrator") : I18n.tr("Standard account")
          tone: AccountManager.admin ? "accent" : "neutral"
        }
      }

      StyledLabel {
        visible: AccountManager.realName !== "" && AccountManager.realName !== root.shownName
        text: I18n.tr("Real name: {0}", AccountManager.realName)
        role: "caption"
      }

      StyledText {
        visible: AccountManager.loaded && !AccountManager.accountsService
        Layout.fillWidth: true
        text: I18n.tr("Without AccountsService the picture stays in ~/.face (the login screen won't show it) and the real name can't be changed here.")
        role: "caption"
      }
    }

    // --- What can be changed ---

    ColumnLayout {
      Layout.alignment: Qt.AlignTop
      spacing: Widget.spacing

      StyledTextButton {
        Layout.fillWidth: true
        text: I18n.tr("Change picture…")
        iconText: "add_a_photo"
        enabled: !AccountManager.busy
        onClicked: AccountManager.pickIcon()
      }

      StyledTextButton {
        Layout.fillWidth: true
        visible: AccountManager.icon !== ""
        text: I18n.tr("Remove picture")
        iconText: "hide_image"
        enabled: !AccountManager.busy
        onClicked: AccountManager.setIcon("")
      }

      StyledTextButton {
        Layout.fillWidth: true
        visible: AccountManager.accountsService
        text: I18n.tr("Edit real name…")
        iconText: "badge"
        enabled: !AccountManager.busy
        onClicked: root.open("name")
      }

      StyledTextButton {
        Layout.fillWidth: true
        text: I18n.tr("Change password…")
        iconText: "password"
        enabled: !AccountManager.busy
        onClicked: root.open("password")
      }
    }
  }

  StyledText {
    visible: AccountManager.error !== ""
    Layout.fillWidth: true
    text: AccountManager.error
    tone: "error"
    role: "body"
  }

  StyledText {
    visible: root.passwordMessage !== "" && root.editing === ""
    Layout.fillWidth: true
    text: root.passwordMessage
    tone: root.passwordFailed ? "error" : "success"
  }

  // --- The real name, edited ---

  FoldingColumn {
    Layout.fillWidth: true
    open: root.editing === "name"
    spacing: Widget.spacing

    StyledSeparator {
      Layout.fillWidth: true
    }

    StyledText {
      text: I18n.tr("Real name")
      role: "label"
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing

      SubmitEntry {
        id: nameEntry
        placeholderText: I18n.tr("Your full name")
        buttonText: I18n.tr("Save")
        canSubmit: !AccountManager.busy && nameEntry.text.trim() !== AccountManager.realName
        onSubmitted: {
          AccountManager.setRealName(nameEntry.text.trim());
          root.editing = "";
        }
      }

      StyledTextButton {
        text: I18n.tr("Cancel")
        onClicked: root.editing = ""
      }
    }
  }

  // --- The password, changed ---

  FoldingColumn {
    Layout.fillWidth: true
    open: root.editing === "password"
    spacing: Widget.spacing

    StyledSeparator {
      Layout.fillWidth: true
    }

    StyledText {
      text: I18n.tr("Change password")
      role: "label"
    }

    GridLayout {
      Layout.fillWidth: true
      columns: root.width > Widget.px(640) ? 3 : 1
      columnSpacing: Widget.spacing
      rowSpacing: Widget.spacing

      PasswordEntry {
        id: currentEntry
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        horizontalAlignment: Text.AlignLeft
        placeholder: I18n.tr("Current password")
        busy: AccountManager.busy
        onAccepted: newEntry.input.forceActiveFocus()
      }

      PasswordEntry {
        id: newEntry
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        horizontalAlignment: Text.AlignLeft
        placeholder: I18n.tr("New password")
        onAccepted: againEntry.input.forceActiveFocus()
      }

      PasswordEntry {
        id: againEntry
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        horizontalAlignment: Text.AlignLeft
        placeholder: I18n.tr("New password again")
        message: root.passwordProblem
        messageIsError: true
        onAccepted: root.changePassword()
      }
    }

    StyledText {
      visible: root.passwordMessage !== ""
      Layout.fillWidth: true
      text: root.passwordMessage
      tone: root.passwordFailed ? "error" : "success"
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing

      StyledText {
        Layout.fillWidth: true
        text: I18n.tr("Your system's password rules apply (length, dictionary words). Other sessions stay signed in.")
        role: "caption"
      }

      StyledTextButton {
        text: AccountManager.busy ? I18n.tr("Changing…") : I18n.tr("Change password")
        enabled: !AccountManager.busy && currentEntry.input.text !== "" && newEntry.input.text !== "" && againEntry.input.text !== "" && root.passwordProblem === ""
        onClicked: root.changePassword()
      }

      StyledTextButton {
        text: I18n.tr("Cancel")
        enabled: !AccountManager.busy
        onClicked: root.editing = ""
      }
    }
  }
}
