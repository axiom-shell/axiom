pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.methods
import qs.components.forms

// A titled group of fields, as on the settings page (editor inspectors): a
// boxed card of its own on the page, flat inside a pane (no fill or border: the
// pane's own); `pageCard` keeps it boxed inside the settings page's own card.
// Children stack with no gap, as a settings card's rows do (a row pads itself,
// FormRow); a non-row child that follows another takes its own
// `Layout.topMargin: Style.space2`. A flat group adds no space around itself:
// the column it sits in spaces it (Style.space2, the settings page's card gap).
// A `pageCard` is hand-built content (no rows): its children keep `headerGap`
// between them.
//
// Inside a pane, `head` says how the title reads (only a flat group with a
// title; a boxed one is as it was): "block" draws it as a head row in the
// field-label look (no control, no hover or click) with the group's rows
// indented one level under it (`rowBase`, which FormRow reads through
// IndentHost); "lead" draws none, the first row leads and its dependents
// indent under it; "section" is the plain SectionHeading, for content that
// isn't rows (a list, a preview, a notice, buttons); "auto" is "lead" when
// the first child is a form that `leads` and there are no `headerExtras`
// (they need the head row), else "block". A flat group whose rows are all
// hidden hides itself: only its direct children count, a form (`allHidden`)
// or a FormRow (`shown`), never anything's `visible`. A non-row child of a
// block takes `Layout.leftMargin: group.inset`.
Surface {
  id: root
  property string title
  property string description
  // Items beside the heading (a status chip, a button)
  property alias headerExtras: extras.data
  // The space between the heading and the first field
  property real headerGap: Style.space2
  // A settings page's hand-built card: boxed whatever it sits on (the page's
  // card around the cards is itself a Surface), as a FoldingCard is
  property bool pageCard: false
  property string head: "auto"
  default property alias content: groupColumn.data

  // How a flat, titled group's heading reads (`head`, resolved): "block",
  // "lead" or "section"
  readonly property string _mode: {
    if (root._boxed || root.title === "" || root.head === "section")
      return "section";
    if (root.head !== "auto")
      return root.head;
    return extras.children.length === 0 && root._firstContent?.leads === true ? "lead" : "block";
  }
  readonly property bool _block: root._mode === "block" && !root._boxed
  // The depth a row of the group starts at (FormRow.base), and whether the
  // rows nest by their tree (SchemaPropertiesForm: not on the settings page)
  readonly property int rowBase: root._block ? 1 : 0
  readonly property bool nests: !root._boxed
  // A block's indent, for a non-row child to line up with its rows
  readonly property real inset: root.rowBase * Widget.spacing * 2

  // The content's children: groupColumn's own heading rows are not
  readonly property var _content: {
    const kids = groupColumn.children;
    const out = [];
    for (let i = 0; i < kids.length; i++) {
      if (kids[i] !== sectionHead && kids[i] !== blockHead)
        out.push(kids[i]);
    }
    return out;
  }
  readonly property var _firstContent: root._content[0] ?? null
  // Flat and every counted child hidden (a form's `allHidden`, a row's
  // `shown`); other children don't count, nor does a group with none
  readonly property bool _empty: {
    if (root._boxed)
      return false;
    let counted = 0;
    for (const kid of root._content) {
      if (kid.allHidden !== undefined) {
        if (kid.allHidden !== true)
          return false;
      } else if (kid.shown !== undefined && "rowBase" in kid) {
        if (kid.shown !== false)
          return false;
      } else {
        continue;
      }
      counted++;
    }
    return counted > 0;
  }

  // Restores the host's own `visible` when the rows return
  Binding {
    target: root
    property: "visible"
    value: false
    when: root._empty
  }

  // The Surface it sits on: the page (or none) takes it as a surface-tone
  // card, any other is a pane, where the group is flat, on the pane's own fill
  readonly property var _host: InkHost.find(root.parent)
  readonly property bool _boxed: root.pageCard || !root._host || root._host.tone === "page"

  Layout.fillWidth: true
  Layout.alignment: Qt.AlignTop
  tone: root._boxed ? "surface" : root._host.tone
  implicitHeight: groupColumn.implicitHeight + (root._boxed ? Style.space3 * 2 : 0)

  // Flat inside a pane: no fill, border or side margins; `color` returns to
  // Surface's own binding on leaving the state
  states: State {
    when: !root._boxed
    PropertyChanges {
      root.color: "transparent"
      root.outlined: false
      groupColumn.anchors.topMargin: 0
      groupColumn.anchors.leftMargin: 0
      groupColumn.anchors.rightMargin: 0
    }
  }

  ColumnLayout {
    id: groupColumn
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Style.space3
    spacing: root.pageCard ? root.headerGap : 0

    // The plain heading (a boxed group, content that isn't rows)
    RowLayout {
      id: sectionHead
      visible: root._mode === "section"
      Layout.fillWidth: true
      Layout.bottomMargin: root.pageCard ? 0 : root.headerGap
      spacing: Widget.spacing

      SectionHeading {
        title: root.title
        description: root.description
      }

      // Where the header extras sit; a block carries them to its head row
      RowLayout {
        id: extras
        spacing: Widget.spacing
        Layout.alignment: Qt.AlignVCenter
        states: State {
          when: root._mode === "block" && !root._boxed
          ParentChange {
            target: extras
            parent: blockHeader
          }
        }
      }
    }

    // A block's head: a row in the field-label look with no control, hover
    // or click; the rows below abut it
    FormRow {
      id: blockHead
      objectName: "blockHead"
      visible: root._block
      first: true
      base: 0
      tinted: false
      hoverable: false
      bodyHeight: blockHeader.implicitHeight

      RowLayout {
        id: blockHeader
        width: parent.width
        spacing: Widget.spacing

        FieldHeader {
          label: root.title
          description: root.description
          Layout.alignment: Qt.AlignVCenter
        }
      }
    }
  }
}
