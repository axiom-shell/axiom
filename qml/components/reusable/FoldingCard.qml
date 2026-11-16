pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A settings card that folds: clicking its header (title, help text,
// chevron) emits `toggled`, and the body below animates shut while
// `collapsed`. Folded with `marked` set, it shows the unsaved-edits dot;
// with a `status` its chip (`statusTone`) sits by the chevron, folded or not.
// The generated cards (SettingsGroupCard), the list cards (EntryListCard)
// and every editor's group (FieldGroup) are built on it.
Surface {
  id: root

  property string title
  // Shown only while unfolded
  property string description
  // A line above the title (the section, in search results)
  property string section
  property bool collapsed: false
  // False: the header doesn't fold it (search results)
  property bool foldable: true
  property bool marked: false
  // A status chip in the header, kept while folded (StatusChip's word and
  // tone; none while empty)
  property string status
  property string statusTone: "neutral"
  // Beside the header, while unfolded (an Add button)
  property alias headerExtras: extras.data
  // The card's rows in order, for `endsShut`. Only a host whose rows aren't
  // its direct children replaces it (SettingsGroupCard); a list, never a value
  property var endRows: root.contentChildren
  // The card ends on a shut fold row (FoldFormRow), so that row's own padding
  // closes it and the card adds none. The last child not hidden decides (a
  // form's `allHidden`, a row's or other child's `shown`), read from those,
  // never from `visible` or heights. Never while folded.
  readonly property bool endsShut: {
    if (root.collapsed)
      return false;
    const kids = root.endRows;
    for (let i = (kids?.length ?? 0) - 1; i >= 0; i--) {
      const kid = kids[i];
      if (!kid || kid.allHidden === true || kid.shown === false)
        continue;
      return kid.shutFold === true;
    }
    return false;
  }
  // False: no header at all (a title-less card: the rows start at the padding)
  property bool headed: true
  // The space between the body's children (0: rows abut)
  property alias bodySpacing: body.spacing
  default property alias content: body.content
  // The body's children, as a list that notifies
  readonly property alias contentChildren: body.contentChildren

  signal toggled

  Layout.fillWidth: true
  tone: "surface"
  implicitHeight: column.implicitHeight + Style.space3 + (root.endsShut ? 0 : Style.space3)

  ColumnLayout {
    id: column
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Style.space3
    spacing: 0

    RowLayout {
      visible: root.headed
      Layout.fillWidth: true
      spacing: Style.space1

      FoldHeader {
        Layout.alignment: Qt.AlignTop
        title: root.title
        description: root.description
        section: root.section
        collapsed: root.collapsed
        foldable: root.foldable
        marked: root.marked
        status: root.status
        statusTone: root.statusTone
        onToggled: root.toggled()
      }

      // Only as wide as what's in it (a layout fills by default, which
      // took half the header from the title and chevron)
      RowLayout {
        id: extras
        visible: !root.collapsed && children.length > 0
        Layout.fillWidth: false
        Layout.alignment: Qt.AlignTop
        spacing: Style.space1
      }
    }

    // The gap under the header folds with the body
    FoldingColumn {
      id: body
      open: !root.collapsed
      topPadding: root.headed ? Style.space2 : 0
      Layout.fillWidth: true
      spacing: Style.space2
    }
  }
}
