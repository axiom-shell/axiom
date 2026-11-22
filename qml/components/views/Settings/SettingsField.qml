pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services.ui
import qs.services.system
import qs.components.forms
import qs.components.methods
import qs.components.reusable

// One settings row: the SchemaField, with a dot while it has an unsaved
// edit (clicking it discards just that edit) and a button that puts it
// back to the schema default, and under a field with `x-hookup` (theme
// integrations) the IntegrationHookup panel, drawn as a FormRow (the
// divider above it, the rail, the fold as its `x-showIf` flips). A field
// with `x-row` is drawn by settings/<Name>.qml instead (given `row` and
// `form`), and the rows its `x-rowDraws` names hide (an object with
// `x-row`: every row under it); an object with `x-fold` is a fold header,
// its rows shown only while it's open (SettingsManager.isFoldOpen), and
// always in a search. A card with an `x-intro` `setup` has one too, a
// `Settings` row (`foldRows`: the rows behind it) hidden while none of them
// shows, its rows `foldedBy` it (`foldedIn` when also inside an `x-fold`).
// A field that writes outside axiom's folders (`Footprint.persistent`) says
// so while the compositor mode is detached (axiom stopping leaves its
// changes), and, off with changes recorded or inferred, offers to remove
// them (recorded ones at once, then asks about the inferred ones, then the
// system defaults). It is a SchemaFormRow (a FoldFormRow drawing the field,
// the same piece the forms' and the onboarder's rows are), and its
// fold-header case (`fold`) is the FoldFormRow's, the same one the editors'
// fold rows are
SchemaFormRow {
  id: root

  readonly property bool isValue: row.kind !== "group"
  // `x-row`: the hand-built piece drawing this field
  readonly property string custom: root.isValue ? (root.row.schema?.["x-row"] ?? "") : ""
  // `x-fold`: this row is the header of its object's fold
  readonly property bool foldHeader: !root.isValue && root.row.fold === true
  // Search results and the changed list show every row they match
  readonly property bool listing: root.form?.listing === true
  readonly property bool foldOpen: root.listing || SettingsManager.isFoldOpen(root.foldHeader ? root.row.path.join(".") : (root.row.foldedBy ?? ""))

  // A row another field's `x-row` draws (`drawnBy`) is drawn there
  readonly property bool foldedInOpen: root.listing || !root.row.foldedIn || SettingsManager.isFoldOpen(root.row.foldedIn)
  // A card's settings fold with nothing shown behind it isn't drawn
  readonly property bool foldHasRows: !root.row.foldRows || root.row.foldRows.some(inner => inner.kind !== "group" && root.form.rowShown(inner))

  // The fold row's own: the header of an `x-fold` or an `x-intro`'s Settings row
  // I18n.tr("Settings") (a card's fold behind its `x-intro`)
  fold: root.foldHeader
  title: I18n.tr(root.row.title)
  open: root.foldOpen
  foldable: !root.listing
  marked: root.foldHeader && (root.row.foldRows ? root.row.foldRows.some(inner => SettingsManager.hasChangesUnder(inner.path.join("."))) : SettingsManager.hasChangesUnder(root.row.path.join(".")))
  onToggled: SettingsManager.setFoldOpen(root.row.path.join("."), !root.foldOpen)

  changed: root.isValue && SettingsManager.isChanged(root.row.path)
  reset: root.isValue ? value => root.form.edited(root.row.path, value) : null
  discard: root.isValue ? () => {
    EditsManager.discardTypingIn(root);
    SettingsManager.discard([root.row.path]);
  } : null
  // Kept drawn while the row folds shut (the row hides once it has); not
  // built for a row drawn otherwise (its `shown` still holds)
  fieldActive: root.custom === "" && !root.foldHeader && !root.row.drawnBy

  shown: root.fieldShown && (!root.row.foldedBy || root.foldOpen) && root.foldedInOpen && root.foldHasRows && !root.row.drawnBy
  // `x-footprint` (Footprint.persistent): the setting writes outside axiom's folders
  readonly property bool footprinted: root.isValue && Footprint.persistent(root.row.schema, SettingsManager.schemaAt([root.row.path[0]]), key => SettingsManager.configValueAt(key.startsWith("/") ? key.slice(1) : key))
  readonly property string ownerPath: root.row.path.join(".")
  readonly property bool badged: root.footprinted && CompositorConfig.mode === "detached"
  // Off, with changes the ledger still holds
  readonly property bool isOff: root.current === Footprint.offValue(root.row.schema)
  readonly property int recordedCount: FootprintManager.undoableFor(root.ownerPath).length
  // What axiom only inferred, asked about once the recorded ones are undone
  readonly property int inferredCount: FootprintManager.inferredFor(root.ownerPath).length
  property bool askedInferred: false
  readonly property bool confirmInferred: root.askedInferred && root.isOff && root.recordedCount === 0 && root.inferredCount > 0
  readonly property bool removable: root.footprinted && root.isOff && (root.recordedCount > 0 || root.inferredCount > 0) && !root.confirmInferred && !root.confirmSystem
  // The system defaults it changed, asked about last
  readonly property int systemCount: FootprintManager.systemFor(root.ownerPath).length
  property bool askedSystem: false
  readonly property bool confirmSystem: root.askedSystem && root.isOff && root.recordedCount === 0 && !root.confirmInferred && root.systemCount > 0
  // The question is for the click it followed: gone once there is nothing
  // to ask about or the setting is on again
  onSystemCountChanged: if (root.systemCount === 0)
    root.askedSystem = false
  onInferredCountChanged: if (root.inferredCount === 0)
    root.askedInferred = false
  onIsOffChanged: if (!root.isOff) {
    root.askedSystem = false;
    root.askedInferred = false;
  }
  readonly property real footprintHeight: root.badged || root.removable || root.confirmInferred || root.confirmSystem ? footprintRow.implicitHeight + Widget.spacing : 0

  // The row's height as if every fold were open, 0 while its own conditions
  // (or what draws it) hide it: what the card's column splits are made from,
  // so a fold opening or shutting never moves a row across columns
  readonly property real flowHeight: root.fieldShown !== false && root.foldHasRows && !root.row.drawnBy ? root.fullHeight : 0

  bodyHeight: (root.custom !== "" ? customRow.implicitHeight : root.foldHeader ? root.foldHeight : root.fieldHeight) + root.extraHeight
  // The hookup and the footprint line, under the field
  extraHeight: hookup.shownHeight + root.footprintHeight
  // Every setting row tints; a click on a switch, toggle or dropdown row
  // acts (SchemaField)
  tinted: root.isValue && root.custom === "" && root.fieldItem?.tinted === true
  hoverable: root.isValue && root.custom === "" && root.fieldItem?.hoverable === true
  railHeight: root.custom !== "" || root.foldHeader ? 0 : root.fieldHeight

  // Outlines the row for a moment (a link to this setting)
  function flash() {
    outline.flash();
  }

  FlashOutline {
    id: outline
    anchors.fill: parent
    anchors.margins: -Widget.spacing / 2
  }

  // Its own job: an `x-row` is a whole block of its own
  StreamedLoader {
    id: customRow
    width: parent.width
    rise: false
    label: `settings row ${root.custom}`
    wanted: root.custom !== ""
    stream: root.custom !== ""
    Component.onCompleted: {
      if (root.custom !== "")
        customRow.setSource(Qt.resolvedUrl(root.custom + ".qml"), {
          "row": root.row,
          "form": root.form
        });
    }
  }

  // Under the field: the integration hookup, then the footprint line
  below: [
    Loader {
      id: hookup
      // Its height and the gap above it, while it shows
      readonly property real shownHeight: {
        const panel = hookup.item as Item;
        return panel && panel.visible ? panel.implicitHeight + Widget.spacing : 0;
      }
      y: Widget.spacing
      width: parent.width
      active: root.isValue && !!root.row.schema?.["x-hookup"]
      sourceComponent: IntegrationHookup {
        integration: root.row.path[root.row.path.length - 1]
        active: root.current === true
      }
    },

    // The footprint's chip and button, under the field (built only while it shows)
    Loader {
      id: footprintRow
      active: root.badged || root.removable || root.confirmInferred || root.confirmSystem
      visible: footprintRow.active
      y: hookup.shownHeight + Widget.spacing
      width: parent.width
      sourceComponent: RowLayout {
        width: footprintRow.width
        spacing: Widget.spacing

        Item {
          visible: root.badged
          implicitWidth: chip.implicitWidth
          implicitHeight: chip.implicitHeight

          // I18n.tr("Stays after axiom stops")
          StatusChip {
            id: chip
            text: I18n.tr("Stays after axiom stops")
            tone: "warning"
          }

          MouseArea {
            id: chipHover
            anchors.fill: parent
            hoverEnabled: true
          }

          LazyLoader {
            active: chipHover.containsMouse
            StyledToolTip {
              target: chip
              maxWidth: Widget.px(320)
              // I18n.tr("This writes outside axiom: quitting axiom or turning it off leaves those changes. Undo them under Changes outside axiom.")
              text: I18n.tr("This writes outside axiom: quitting axiom or turning it off leaves those changes. Undo them under Changes outside axiom.")
            }
          }
        }

        StyledTextButton {
          visible: root.removable
          text: I18n.tr("Remove its changes")
          onClicked: {
            root.askedSystem = root.systemCount > 0;
            root.askedInferred = true;
            if (root.recordedCount > 0)
              FootprintManager.undoOwner(root.ownerPath);
          }
        }

        ConfirmLine {
          visible: root.confirmInferred
          Layout.fillWidth: true
          // I18n.tr("axiom also found 1 change here it has no record of making. Remove it too? Keep leaves it as it is.")
          question: root.inferredCount === 1 ? I18n.tr("axiom also found 1 change here it has no record of making. Remove it too? Keep leaves it as it is.") : I18n.tr("axiom also found {0} changes here it has no record of making. Remove them too? Keep leaves them as they are.", root.inferredCount)
          confirmText: I18n.tr("Remove")
          onKept: root.askedInferred = false
          onConfirmed: {
            root.askedInferred = false;
            FootprintManager.undo(FootprintManager.inferredFor(root.ownerPath).map(row => row.id), true);
          }
        }

        ConfirmLine {
          visible: root.confirmSystem
          Layout.fillWidth: true
          question: I18n.tr("Also put back the system defaults axiom changed here ({0})? Keep leaves them as they are.", root.systemCount)
          confirmText: I18n.tr("Put back")
          onKept: root.askedSystem = false
          onConfirmed: {
            root.askedSystem = false;
            FootprintManager.undo(FootprintManager.systemFor(root.ownerPath).map(row => row.id));
          }
        }

        Item {
          visible: !root.confirmSystem && !root.confirmInferred
          Layout.fillWidth: true
        }
      }
    }
  ]
}
