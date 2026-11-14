import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts
import qs.components.views.base

// Text fit at every scale, font size, density and width (the layout harness,
// scripts/qml_modules.py --layout): a piece holds its texts, a one-line text
// has one line, a wrapping one is capped, a long unbroken token never leaves
// its box; StyledText is native at rest and distance field under a zoom.
TestCase {
  id: root

  name: "TextFit"
  when: windowShown
  visible: true
  width: 600
  height: 400

  Harness {
    id: harness
  }

  FontMetrics {
    id: fontMetrics

    font.family: Appearance.fontFamily
    font.pixelSize: 14
  }

  Component {
    id: textComp

    StyledText {}
  }

  Component {
    id: menuRowComp

    MenuRow {
      icon: "folder"
    }
  }

  Component {
    id: moduleHeaderComp

    ModuleHeader {
      icon: "hard_drive"
    }
  }

  Component {
    id: moduleHeaderTrailComp

    ModuleHeader {
      readonly property Item button: trailButton
      icon: "wallpaper"

      StyledText {
        Layout.maximumWidth: Widget.textPx(160)
        overflow: "line"
        text: "Generating themes for every wallpaper in the folder"
      }
      StyledIconButton {
        id: trailButton
        iconText: "skip_next"
      }
    }
  }

  Component {
    id: cardHeaderComp

    CardHeader {}
  }

  Component {
    id: emptyStateComp

    EmptyState {
      icon: "inbox"
    }
  }

  Component {
    id: keyMapComp

    KeyboardMap {}
  }

  Component {
    id: zoomComp

    Item {
      property real contentZoom: 0.9
      property alias text: inner

      StyledText {
        id: inner

        text: "zoomed"
      }
    }
  }

  Component {
    id: toolBarComp

    ToolBar {
      searchable: true
      searchPlaceholder: "Search"
      count: 12
      leading: StyledTextButton {
        text: "Layout"
      }
      trailing: [
        StyledTextButton {
          text: "New layout"
        },
        StyledTextButton {
          text: "Identify"
        }
      ]
    }
  }

  Component {
    id: listSectionComp

    ListSection {
      title: "Your rules"
      count: 3
      hint: "Drag to order: the first match wins"
      collapsible: true
      Item {
        implicitHeight: 10
        Layout.fillWidth: true
      }
    }
  }

  Component {
    id: inspectorHeaderComp

    InspectorHeader {
      icon: "widgets"
      title: "A custom widget"
      subtitle: "/home/user/.config/scripts/a-long-script-name.sh --flag"
      canDuplicate: true
      revertable: true
      canRemove: true
      closable: true
    }
  }

  Component {
    id: plainTabsComp

    StyledTabBar {
      tabs: ["A", "B"]
      currentIndex: 0
    }
  }

  Component {
    id: scrollTabsComp

    StyledTabBar {
      scrollable: true
      tabs: ["Layout", "Surface", "Style", "Behaviour"]
      currentIndex: 0
    }
  }

  Component {
    id: markedTabsComp

    StyledTabBar {
      tabs: ["Layout", "Surface", "Style", "Behaviour"]
      marked: [1]
      currentIndex: 0
    }
  }

  Component {
    id: toolPaneComp

    ToolPane {
      title: "Window rules"
      Rectangle {
        objectName: "paneChild"
        implicitHeight: 40
        Layout.fillWidth: true
      }
    }
  }

  Component {
    id: workAreaComp

    WorkArea {
      title: "Canvas"
      showActions: false
      status: [
        StyledText {
          objectName: "statusChild"
          visible: false
          role: "caption"
          text: "Fits"
        }
      ]
    }
  }

  Component {
    id: richRowComp

    ListEntryRow {
      id: rich

      icon: "folder"
      label: "An entry name long enough that it has to elide before anything else"
      changed: true
      badges: [
        StatusChip {
          text: "One"
        },
        StatusChip {
          text: "Two"
        },
        StatusChip {
          text: "Three"
        }
      ]

      RowAction {
        row: rich
        iconText: "content_copy"
      }
      RowAction {
        row: rich
        iconText: "close"
      }
    }
  }

  Component {
    id: keyRowsComp

    Column {
      id: col

      property alias rowA: rowA
      property alias rowB: rowB
      property alias actionA1: a1
      property alias actionA2: a2
      property alias after: after
      property bool blocked: true
      property int removed: 0
      property int escapesSeen: 0
      property int escapes: 0

      Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape)
          col.escapesSeen++;
      }

      ListEntryRow {
        id: rowA

        width: 300
        escapeClears: true
        label: "A"
        onRemoveRequested: if (!col.blocked)
          col.removed++
        onEscapePressed: col.escapes++

        RowAction {
          id: a1
          row: rowA
          iconText: "content_copy"
        }
        RowAction {
          id: a2
          row: rowA
          iconText: "close"
        }
      }
      ListEntryRow {
        id: rowB

        width: 300
        label: "B"

        RowAction {
          row: rowB
          iconText: "close"
        }
      }
      Rectangle {
        id: after

        width: 10
        height: 10
        activeFocusOnTab: true
      }
    }
  }

  Component {
    id: groupColumnsComp

    GroupColumns {
      Rectangle {
        objectName: "a"
        implicitHeight: 100
      }
      Rectangle {
        objectName: "b"
        implicitHeight: 200
      }
      Rectangle {
        objectName: "hidden"
        implicitHeight: 150
        visible: false
      }
      Rectangle {
        objectName: "d"
        implicitHeight: 120
      }
    }
  }

  property bool sectionOpen: true

  readonly property var strings: ({
      "en": "Open the settings file",
      "ja": "設定ファイルを開く",
      "enLong": "Open the settings file in the default editor for the current project",
      "token": "a".repeat(40)
    })

  // The first test of the file fails loudly on a runner without the font,
  // instead of every row passing vacuously
  function test_00_font_is_present() {
    harness.configure({});
    verify(fontMetrics.advanceWidth("W") > 0);
    compare(Appearance.fontFamily, "DejaVu Sans Mono");
  }

  function rows() {
    const out = [];
    for (const scale of [75, 100, 150])
      for (const fontSize of [8, 14, 32])
        for (const density of ["compact", "roomy"])
          for (const width of ["narrow", "wide"])
            for (const key of ["en", "ja", "enLong", "token"])
              out.push({
                "tag": `${scale}% font ${fontSize} ${density} ${width} ${key}`,
                "scale": scale,
                "fontSize": fontSize,
                "density": density,
                "width": width,
                "key": key
              });
    return out;
  }

  function test_menu_row_holds_its_text_data() {
    return rows();
  }

  function test_menu_row_holds_its_text(data) {
    harness.configure(data);
    // the row's fixed parts (padding, icon, trailing detail) and then a measure of text
    const fixed = Widget.padding * 2 + Style.iconMd + Widget.spacing * 2 + Widget.textPx(60);
    const row = createTemporaryObject(menuRowComp, root, {
      "text": strings[data.key],
      "trailing": "Ctrl+O",
      "width": fixed + (data.width === "narrow" ? Widget.textPx(140) : Widget.textPx(400))
    });
    waitForRendering(row);
    compare(harness.containedProblems(row), []);
    verify(row.implicitHeight >= Math.ceil(1.5 * Appearance.fontSize), "the row holds a line of its font");
    for (const t of harness.texts(row)) {
      if (t.text === row.text)
        compare(t.lineCount, 1);
    }
  }

  // A module's header: the title elides in its row before the trailing items
  function test_module_header_holds_its_title_data() {
    return rows();
  }

  function test_module_header_holds_its_title(data) {
    harness.configure(data);
    const header = createTemporaryObject(moduleHeaderComp, root, {
      "title": strings[data.key],
      "width": data.width === "narrow" ? Widget.textPx(140) : Widget.textPx(400)
    });
    waitForRendering(header);
    compare(harness.containedProblems(header), []);
    for (const t of harness.texts(header)) {
      if (t.text === header.title)
        compare(t.lineCount, 1);
    }
  }

  function test_module_header_keeps_trailing_items_inside_data() {
    return rows();
  }

  function test_module_header_keeps_trailing_items_inside(data) {
    harness.configure(data);
    const header = createTemporaryObject(moduleHeaderTrailComp, root, {
      "title": strings[data.key],
      "width": Widget.textPx(400)
    });
    waitForRendering(header);
    // the harness has no icon font, so the glyph's name paints as wide text: judge the label, the button's box below
    compare(harness.containedProblems(header).filter(p => !p.startsWith('"skip_next"')), []);
    compare(header.button.width, header.button.size);
    const at = header.button.mapToItem(header, 0, 0);
    verify(at.x + header.button.width <= header.width + 0.5);
  }

  // A panel's header: one line of title, with the Save and Discard buttons
  function test_card_header_holds_its_title_data() {
    return rows();
  }

  function test_card_header_holds_its_title(data) {
    harness.configure(data);
    const header = createTemporaryObject(cardHeaderComp, root, {
      "title": strings[data.key],
      "dirty": true,
      "height": Widget.height * 2,
      // never under what its two icon buttons need (the narrowest a panel is)
      "width": Math.max(data.width === "narrow" ? Widget.textPx(140) : Widget.textPx(400), Widget.height * 4 + Widget.spacing * 3)
    });
    waitForRendering(header);
    compare(harness.containedProblems(header), []);
    for (const t of harness.texts(header)) {
      if (t.text === header.title)
        compare(t.lineCount, 1);
    }
  }

  // An empty state: its text and hint wrap inside `maxWidth`
  function test_empty_state_holds_its_text_data() {
    return rows();
  }

  function test_empty_state_holds_its_text(data) {
    harness.configure(data);
    const state = createTemporaryObject(emptyStateComp, root, {
      "text": strings[data.key],
      "hint": strings[data.key],
      "maxWidth": data.width === "narrow" ? Widget.textPx(140) : Widget.textPx(400)
    });
    waitForRendering(state);
    compare(harness.containedProblems(state), []);
  }

  // An empty state given less room than its full height shows only the icon;
  // given its full height it keeps the text, hint and button
  function test_empty_state_keeps_to_its_room_data() {
    return rows();
  }

  function test_empty_state_keeps_to_its_room(data) {
    harness.configure(data);
    const state = createTemporaryObject(emptyStateComp, root, {
      "text": strings[data.key],
      "hint": strings[data.key],
      "actionText": "Retry",
      "maxWidth": Widget.textPx(400)
    });
    waitForRendering(state);
    const full = state.implicitHeight;
    state.availableHeight = full - 1;
    waitForRendering(state, 1000);
    verify(state.implicitHeight <= state.availableHeight + 0.5, `${state.implicitHeight} in ${state.availableHeight}`);
    state.availableHeight = full;
    waitForRendering(state, 1000);
    compare(state.implicitHeight, full);
  }

  // The key map: every blank (modifier) key's name whole in its key, and the
  // block scrolling sideways, never squeezing a keycap, when a big font makes
  // its keys wider than the panel
  function test_keyboard_map_keeps_modifier_names_whole_data() {
    return [
      {
        "tag": "520 px, font 14",
        "fontSize": 14,
        "width": 520,
        "scrolls": false
      },
      {
        "tag": "400 px, font 24",
        "fontSize": 24,
        "width": 400,
        "scrolls": true
      }
    ];
  }

  function find(item, test, out) {
    if (test(item))
      out.push(item);
    for (const child of item.children)
      find(child, test, out);
    if (item.contentItem && item.contentItem !== item)
      find(item.contentItem, test, out);
    return out;
  }

  function test_keyboard_map_keeps_modifier_names_whole(data) {
    harness.configure({
      "fontSize": data.fontSize
    });
    const map = createTemporaryObject(keyMapComp, root, {
      "width": data.width
    });
    waitForRendering(map);
    const keys = find(map, it => it.blank === true && it.entry !== undefined && it.entry.label !== "", []);
    verify(keys.length > 0);
    for (const key of keys) {
      const label = find(key, it => it.text === key.entry.label && it.lineCount !== undefined, [])[0];
      verify(label, key.entry.label);
      compare(label.truncated, false, key.entry.label);
      verify(label.implicitWidth <= key.width - Widget.px(4) + 0.5, `${key.entry.label}: ${label.implicitWidth} in ${key.width}`);
    }
    const scroller = find(map, it => it.flickableDirection !== undefined, [])[0];
    verify(scroller);
    compare(scroller.contentWidth > scroller.width, data.scrolls);
    verify(scroller.contentHeight > 0);
    compare(scroller.height, scroller.contentHeight);
  }

  function test_roles_hold_their_text_data() {
    const out = [];
    for (const row of rows())
      for (const role of ["micro", "caption", "body", "label", "title", "headline", "display"])
        out.push(Object.assign({}, row, {
          "role": role,
          "tag": `${role} ${row.tag}`
        }));
    return out.filter((_, i) => i % 7 === 0);
  }

  function test_roles_hold_their_text(data) {
    harness.configure(data);
    const box = createTemporaryObject(boxComp, root, {
      "width": data.width === "narrow" ? Widget.textPx(140) : Widget.textPx(400)
    });
    // a text with a bound (a fillWidth in a layout) in its box; a `none` text (a figure) is sized by its box
    const text = textComp.createObject(box, {
      "role": data.role,
      "text": strings[data.key],
      "maxLines": 3,
      "width": box.width
    });
    waitForRendering(box);
    const overflow = text.overflow || text._role.overflow;
    if (overflow !== "none")
      compare(harness.containedProblems(box), []);
    if (overflow === "line")
      compare(text.lineCount, 1);
    else if (overflow === "wrap")
      verify(text.lineCount <= 3);
  }

  Component {
    id: boxComp

    Item {
      height: 400
    }
  }

  // Native outside a zoom host, distance field inside one
  function test_render_type() {
    harness.configure({});
    const plain = createTemporaryObject(textComp, root, {
      "text": "plain"
    });
    compare(plain.renderType, Text.NativeRendering);
    const zoomed = createTemporaryObject(zoomComp, root);
    compare(zoomed.text.renderType, Text.QtRendering);
    zoomed.contentZoom = 1;
    compare(zoomed.text.renderType, Text.NativeRendering);
  }

  // The toolbar: one line wide, wrapping its trailing controls under the
  // search narrow, the search never under 160 px of text
  function test_tool_bar_wraps_and_keeps_its_search_data() {
    return rows().filter(r => r.key === "en");
  }

  function test_tool_bar_wraps_and_keeps_its_search(data) {
    harness.configure(data);
    const wide = data.width === "wide";
    const bar = createTemporaryObject(toolBarComp, root, {
      "width": wide ? Widget.textPx(900) : Widget.textPx(360)
    });
    waitForRendering(bar);
    compare(bar.wrapped, !wide);
    compare(harness.containedProblems(bar, true), []);
    const search = find(bar, it => it.clearable !== undefined, [])[0];
    verify(search);
    verify(search.width >= Widget.textPx(160) - 0.5, `${search.width}`);
    const identify = find(bar, it => it.text === "Identify" && it.lineCount !== undefined, [])[0];
    verify(identify);
    const y = identify.mapToItem(bar, 0, 0).y;
    if (wide)
      verify(y < search.height, `one line: ${y}`);
    else
      verify(y >= search.height, `second line: ${y}`);
  }

  // A section's header holds its title and count; a click while collapsible
  // emits `toggled` and leaves a bound `open` bound
  function test_list_section_holds_its_header_data() {
    return rows().filter(r => r.key === "en" || r.key === "token");
  }

  function test_list_section_holds_its_header(data) {
    harness.configure(data);
    const section = createTemporaryObject(listSectionComp, root, {
      "width": data.width === "narrow" ? Widget.textPx(200) : Widget.textPx(500),
      "title": strings[data.key]
    });
    section.open = Qt.binding(() => root.sectionOpen);
    waitForRendering(section);
    compare(harness.containedProblems(section, true), []);
    const toggles = createTemporaryObject(spyComp, root, {
      "target": section,
      "signalName": "toggled"
    });
    mouseClick(section, Widget.px(10), Widget.height / 2);
    compare(toggles.count, 1);
    compare(section.open, true);
    root.sectionOpen = false;
    compare(section.open, false);
    root.sectionOpen = true;
  }

  Component {
    id: spyComp

    SignalSpy {}
  }

  // An inspector header with every standard action: its texts inside, each
  // button shown and inside it
  function test_inspector_header_holds_its_actions_data() {
    return rows().filter(r => r.key === "en");
  }

  function test_inspector_header_holds_its_actions(data) {
    harness.configure(data);
    const header = createTemporaryObject(inspectorHeaderComp, root, {
      // never under the icon well and the four buttons
      "width": data.width === "narrow" ? Math.max(Widget.textPx(300), Widget.iconButton * 4 + (Widget.height + Widget.px(4)) + Widget.spacing * 6 + Widget.textPx(60)) : Widget.textPx(600)
    });
    waitForRendering(header);
    compare(harness.containedProblems(header, true), []);
    const buttons = find(header, it => it.iconText !== undefined && it.iconText !== "" && it.tooltipText !== undefined, []);
    compare(buttons.length, 4);
    for (const button of buttons) {
      verify(button.visible, button.iconText);
      const at = button.mapToItem(header, 0, 0);
      verify(at.x >= -0.5 && at.x + button.width <= header.width + 0.5, `${button.iconText} at ${at.x} in ${header.width}`);
    }
  }

  // A scrolling tab strip: four tabs at a big font in a narrow pane keep
  // every label whole, and the underline follows the current tab
  function test_scrollable_tabs_keep_their_labels_whole() {
    harness.configure({
      "fontSize": 24
    });
    const bar = createTemporaryObject(scrollTabsComp, root, {
      "width": Widget.textPx(240)
    });
    waitForRendering(bar);
    const flick = find(bar, it => it.flickableDirection !== undefined, [])[0];
    verify(flick);
    verify(flick.contentWidth > flick.width, "the strip overflows");
    for (const label of bar.tabs) {
      const text = find(bar, it => it.text === label && it.truncated !== undefined, [])[0];
      verify(text, label);
      compare(text.truncated, false, label);
    }
    bar.currentIndex = 3;
    tryVerify(() => flick.contentX > 0);
    const tab = bar._current;
    verify(tab.x - flick.contentX >= -0.5 && tab.x + tab.width - flick.contentX <= flick.width + 0.5, "the current tab is in view");
    const mark = find(bar, it => it.radius !== undefined && it.height === Widget.px(2) && it.visible, [])[0];
    verify(mark);
    tryVerify(() => Math.abs(mark.x + mark.width / 2 - (tab.x + tab.width / 2)) < 1);
    bar.width = Widget.textPx(2000);
    waitForRendering(bar);
    fuzzyCompare(bar._current.width, bar._current.implicitWidth, 1, "a tab keeps its own width");
  }

  // A marked tab shows one unsaved dot, after its label and inside the tab
  function test_marked_tab_shows_one_dot_after_its_label() {
    harness.configure({});
    const bar = createTemporaryObject(markedTabsComp, root, {
      "width": Widget.textPx(400)
    });
    waitForRendering(bar);
    // (find walks a tab's content item twice)
    const dots = find(bar, it => it.shown !== undefined && it.onAccent !== undefined, []).filter((d, i, all) => all.indexOf(d) === i);
    compare(dots.length, 4);
    tryVerify(() => dots.filter(dot => dot.visible).length === 1);
    const dot = dots.find(d => d.visible);
    const tab = find(bar, it => it.text === "Surface" && it.checked !== undefined, [])[0];
    verify(tab, "the Surface tab");
    const label = find(tab, it => it.text === "Surface" && it.truncated !== undefined, [])[0];
    const dotAt = dot.mapToItem(bar, 0, 0).x;
    const labelAt = label.mapToItem(bar, 0, 0).x;
    const tabAt = tab.mapToItem(bar, 0, 0).x;
    verify(dotAt >= labelAt + label.width - 0.5, "after the label");
    verify(dotAt + dot.width <= tabAt + tab.width + 0.5, "inside its tab");
    compare(dots.indexOf(dot), 1, "on the second tab");
  }

  // A tab bar that does not scroll keeps the tab's own padding
  function test_plain_tabs_keep_their_padding() {
    harness.configure({});
    const bar = createTemporaryObject(plainTabsComp, root, {
      "width": Widget.textPx(300)
    });
    waitForRendering(bar);
    verify(bar._current);
    const bare = Qt.createQmlObject("import QtQuick.Controls; TabButton {}", root);
    compare(bar._current.leftPadding, bare.leftPadding, "the tab's own left padding");
    compare(bar._current.rightPadding, bare.rightPadding, "and right");
    bare.destroy();
  }

  // A row with three badges and two actions at the narrowest width: every
  // badge visible and inside the row, the actions' room reserved while they
  // are hidden
  function test_list_entry_row_keeps_its_badges_data() {
    return rows().filter(r => r.key === "en");
  }

  function test_list_entry_row_keeps_its_badges(data) {
    harness.configure(data);
    const row = createTemporaryObject(richRowComp, root, {
      "width": 4000
    });
    waitForRendering(row);
    verify(!row.revealed);
    // The narrowest: what the badges, the dot and the actions need, and 60 px of text for the name
    const parts = find(row, it => (it.tone !== undefined && it.border !== undefined) || (it.iconText !== undefined && it.row !== undefined), []);
    let needed = Widget.padding * 1.5 + Style.iconSm * 1.5 + Widget.px(20) + Widget.textPx(60);
    for (const part of parts)
      needed += part.width + Widget.spacing;
    row.width = data.width === "narrow" ? Math.max(Widget.textPx(300), needed) : Math.max(Widget.textPx(500), needed);
    waitForRendering(row);
    const chips = find(row, it => it.tone !== undefined && it.text !== undefined && it.lineCount === undefined && it.border !== undefined, []);
    verify(chips.length >= 3, `${chips.length} chips`);
    const actions = find(row, it => it.iconText !== undefined && it.row !== undefined, []);
    compare(actions.length, 2);
    for (const action of actions) {
      verify(action.width > 0);
      compare(action.opacity, 0);
      const at = action.mapToItem(row, 0, 0);
      verify(at.x >= 0 && at.x + action.width <= row.width + 0.5, "action inside");
    }
    const firstAction = actions[0].mapToItem(row, 0, 0).x;
    for (const chip of chips) {
      const at = chip.mapToItem(row, 0, 0);
      verify(chip.visible && at.x >= 0 && at.x + chip.width <= row.width + 0.5, `${chip.text} inside: ${at.x} + ${chip.width} of ${row.width}`);
      verify(at.x + chip.width <= firstAction + 0.5, `${chip.text} clear of the actions`);
    }
  }

  // The lists' keyboard route
  function test_list_rows_keyboard_route() {
    harness.configure({});
    const rows = createTemporaryObject(keyRowsComp, root);
    waitForRendering(rows);
    // Up and Down walk the rows, skipping their actions
    rows.rowA.forceActiveFocus();
    verify(rows.rowA.activeFocus);
    keyClick(Qt.Key_Down);
    verify(rows.rowB.activeFocus, "Down reaches the next row");
    keyClick(Qt.Key_Down);
    verify(rows.rowB.activeFocus, "and stops at the end of the list");
    keyClick(Qt.Key_Up);
    verify(rows.rowA.activeFocus, "Up goes back");
    // Delete runs the page's remove; a page that blocks it changes nothing
    keyClick(Qt.Key_Delete);
    compare(rows.removed, 0);
    rows.blocked = false;
    keyClick(Qt.Key_Delete);
    compare(rows.removed, 1);
    // Escape: an unselected row leaves it to the host, a selected one takes it
    keyClick(Qt.Key_Escape);
    compare(rows.escapes, 0);
    compare(rows.escapesSeen, 1);
    rows.rowA.selected = true;
    keyClick(Qt.Key_Escape);
    compare(rows.escapes, 1);
    compare(rows.escapesSeen, 1);
    // A selected row of a list that clears nothing leaves Escape to the host
    rows.rowA.selected = false;
    rows.rowB.selected = true;
    rows.rowB.forceActiveFocus();
    keyClick(Qt.Key_Escape);
    compare(rows.escapes, 1);
    compare(rows.escapesSeen, 2);
    rows.rowB.selected = false;
    rows.rowA.selected = true;
    rows.rowA.forceActiveFocus();
    // Tab: the row's actions, then out of the list, never the next row
    keyClick(Qt.Key_Tab);
    verify(rows.actionA1.activeFocus, "Tab reaches the first action");
    keyClick(Qt.Key_Tab);
    verify(rows.actionA2.activeFocus, "then the second");
    keyClick(Qt.Key_Tab);
    verify(rows.after.activeFocus, "then the item after the list");
    verify(!rows.rowB.activeFocus);
    rows.actionA1.forceActiveFocus();
    keyClick(Qt.Key_Backtab);
    verify(rows.rowA.activeFocus, "Shift+Tab from the first action is the row");
  }

  // A pane with an empty state hides its body and shows the state, top-anchored at the same place in the three kinds (so its icon stays still)
  function test_tool_pane_shows_its_empty_state() {
    harness.configure({});
    const pane = createTemporaryObject(toolPaneComp, root, {
      "width": 420,
      "height": 500,
      "emptyKind": "none",
      "emptyIcon": "widgets",
      "emptyText": "No rules yet",
      "emptyHint": "Add one",
      "emptyActionText": "Add a rule"
    });
    waitForRendering(pane);
    const child = find(pane, it => it.objectName === "paneChild", [])[0];
    verify(child);
    verify(!child.visible, "the body is hidden");
    const states = () => Array.from(new Set(find(pane, it => it.hint !== undefined && it.actionText !== undefined && it.availableHeight !== undefined, [])));
    compare(states().length, 1);
    const none = states()[0].mapToItem(pane, 0, 0).y;
    pane.emptyKind = "select";
    pane.emptyText = "Select a rule";
    pane.emptyHint = "";
    pane.emptyActionText = "";
    waitForRendering(pane);
    compare(states().length, 1);
    compare(states()[0].mapToItem(pane, 0, 0).y, none);
    pane.emptyKind = "results";
    pane.emptyText = "Nothing matches";
    pane.emptyActionText = "Clear search";
    waitForRendering(pane);
    compare(states()[0].mapToItem(pane, 0, 0).y, none);
    pane.emptyKind = "";
    waitForRendering(pane);
    verify(child.visible, "the body is back");
    compare(states().length, 0);
  }

  // A status line hidden at load shows once its child does
  function test_work_area_status_line_shows_later() {
    harness.configure({});
    const area = createTemporaryObject(workAreaComp, root, {
      "width": 400,
      "height": 300
    });
    waitForRendering(area);
    const child = find(area, it => it.objectName === "statusChild", [])[0];
    verify(child);
    const before = area.implicitHeight;
    child.visible = true;
    waitForRendering(area);
    verify(child.visible, "the status line shows");
    verify(area.implicitHeight > before, "and takes room");
  }

  // Groups flow into columns: a hidden one takes no column, none overlaps
  // another, and showing it later lays it out again
  function test_group_columns_flow_their_units() {
    harness.configure({});
    const columns = createTemporaryObject(groupColumnsComp, root, {
      "width": 1240
    });
    const unit = name => find(columns, it => it.objectName === name, [])[0];
    tryVerify(() => columns.height > 0);
    compare(columns.count, 2);
    compare(unit("a").x, 0);
    compare(unit("a").y, 0);
    compare(unit("b").y, unit("a").height + Style.space5);
    compare(unit("d").x, unit("a").width + Style.space5);
    compare(unit("d").y, 0);
    verify(unit("a").width >= Style.columnMin && unit("a").width <= Math.round(1.25 * Style.columnTarget), `${unit("a").width}`);
    compare(unit("hidden").width, 0);
    unit("hidden").visible = true;
    tryVerify(() => unit("hidden").width > 0);
    const placed = ["a", "b", "hidden", "d"].map(unit);
    for (const one of placed)
      for (const other of placed)
        if (one !== other && one.x === other.x)
          verify(one.y + one.height <= other.y || other.y + other.height <= one.y, `${one.objectName} overlaps ${other.objectName}`);
  }
}
