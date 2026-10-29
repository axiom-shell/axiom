pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.ui
import qs.components.methods
import qs.components.reusable
import qs.components.content.base

// Settings page, right: the selected category's groups as cards in two
// newspaper columns (wide ones across both), split by their measured
// heights so both end together, or every setting matching the search,
// under its category's name. Acts as the `form` for its SchemaField rows.
Item {
  id: root

  required property var categories
  // The selected entry of `categories`
  required property var category

  readonly property var schema: ConfigManager.configSchema
  // The search typed, taken once typing pauses (`queryDelay`), so a burst
  // of keystrokes builds the results once; clearing it takes at once
  property string query: ""
  readonly property bool searching: query !== ""
  // Listing matches from every category: a search, or the settings
  // changed from their defaults (SettingsManager.changedOnly), or both
  readonly property bool listing: root.searching || SettingsManager.changedOnly

  Component.onCompleted: {
    root.query = root._typed;
    root._lastPageIndex = root._pageIndex;
  }

  readonly property string _typed: SettingsManager.query.trim().toLowerCase()
  on_TypedChanged: {
    if (root._typed === "") {
      queryDelay.stop();
      root.query = "";
    } else {
      queryDelay.restart();
    }
  }

  // A quiet spell after a keystroke (a behaviour timing, not an animation)
  Timer {
    id: queryDelay
    interval: 150
    onTriggered: root.query = root._typed
  }

  signal edited(var path, var value)
  onEdited: (path, value) => SettingsManager.setValue(path, value)
  // A row's edit (SchemaField's form)
  function edit(path, value) {
    root.edited(path, value);
  }
  // A text field's keystroke: unsaved at once, applied on its commit
  signal typed(var path, var value)
  onTyped: (path, value) => SettingsManager.setDraftValue(path, value)

  function valueAt(path) {
    return Utils.valueAt(SettingsManager.localConfig, path);
  }

  // Whether an `x-showIf`-style condition holds, its plain keys being
  // siblings under `parent` (a key path)
  function conditionHolds(condition, parent) {
    return SchemaLayout.showIfHolds(condition, key => key.startsWith("/") ? SettingsManager.configValueAt(key.slice(1)) : root.valueAt(SchemaLayout.keyPath(parent, key)));
  }

  // A card from an object with `x-showIf` (e.g. managed-only settings), or
  // one whose every row is hidden by its own `x-showIf` (an `x-group` card)
  function _groupShown(group) {
    if (!root.conditionHolds(group.showIf, group.showIfParent))
      return false;
    return group.kind !== "rows" || group.rows.length === 0 || group.rows.some(row => row.kind === "group" || (root.conditionHolds(row.schema?.["x-showIf"], row.path.slice(0, -1)) && (row.groupShowIf ?? []).every(outer => root.conditionHolds(outer.condition, outer.path))));
  }

  // Every category's cards with rows, carrying their category's name, as
  // what a search reads (SettingsSearch.index): taken once while listing,
  // again only when the schema, the categories shown or the language
  // change. Hand-built cards have no rows to search
  readonly property var _searchIndex: {
    // (I18n.current: read so a new language indexes again)
    if (!root.listing || !I18n.current)
      return [];
    const groups = [].concat(...root.categories.map(category => SchemaLayout.categoryGroups(root.schema, category).filter(group => group.kind !== "card").map(group => Object.assign({}, group, {
          "category": category.name,
          "categoryIcon": category.icon
        }))));
    return SettingsSearch.index(groups, text => I18n.tr(text));
  }

  // From the schema, category, search and the changed set only: never
  // from config values, so editing doesn't rebuild the cards. Listed
  // results carry their category's name
  readonly property var groups: root.listing ? SettingsSearch.filter(root._searchIndex, root.query, SettingsManager.changedSet, SettingsManager.changedOnly) : SchemaLayout.categoryGroups(root.schema, root.category)

  // Which groups are shown, as a string so it only notifies when that
  // actually changes, not on every edit
  readonly property string _shownKey: root.groups.map(group => root._groupShown(group) ? "1" : "0").join("")

  // The selected category's shown cards, for the sidebar to jump to
  readonly property var shownGroups: {
    if (root.listing)
      return [];
    const shown = root._shownKey;
    return root.groups.filter((group, i) => shown[i] === "1");
  }

  // The shown cards that can fold (hand-built ones only with `x-cardFolds`,
  // and none while searching)
  readonly property var foldableKeys: {
    if (root.listing)
      return [];
    const shown = root._shownKey;
    return root.groups.filter((group, i) => shown[i] === "1" && (group.kind === "rows" || group.folds)).map(group => group.key);
  }
  readonly property bool allFolded: root.foldableKeys.length > 0 && root.foldableKeys.every(key => SettingsManager.isCollapsed(key))

  // Lays the columns out again once the cards have folded. Folding one
  // card doesn't, so it never moves the cards across columns
  signal relayout

  function setAllFolded(value) {
    SettingsManager.setCollapsed(root.foldableKeys, value);
    root.relayout();
  }

  // The shown groups in two columns: one block per category while
  // searching (`name`, its heading), else one for the selected category
  readonly property var blocks: {
    const shown = root._shownKey;
    const blocks = [];
    root.groups.forEach((group, i) => {
      if (shown[i] !== "1")
        return;
      const name = group.category ?? "";
      if (blocks.length === 0 || blocks[blocks.length - 1].name !== name)
        blocks.push({
          "name": name,
          "icon": group.categoryIcon ?? "",
          "groups": []
        });
      blocks[blocks.length - 1].groups.push(group);
    });
    return blocks;
  }

  // The card each group key is drawn by, to scroll to
  property var _cards: ({})

  Connections {
    target: SettingsManager
    function onJumpRequested(key, unfolded) {
      jumpDelay.interval = unfolded ? Appearance.animNormal : 0;
      jumpDelay.restart();
    }
  }

  // Waits for an unfolding card to open, so the page is long enough to
  // bring it to the top
  Timer {
    id: jumpDelay
    onTriggered: root._takeJump()
  }

  // Makes SettingsManager's pending jump once its card is laid out: now,
  // or when its block settles (the page was just built, or the category
  // just changed). Its row centred and outlined, else the card at the top
  function _takeJump() {
    const jump = SettingsManager.pendingJump;
    if (!jump)
      return;
    const card = root._cards[jump.key];
    if (card?.settling)
      return;
    // No such card shown (hidden, or listing results): nothing to wait for once
    // every block has settled
    if (!card) {
      for (let i = 0; i < blocksRepeater.count; i++)
        if (blocksRepeater.itemAt(i)?.settling)
          return;
      SettingsManager.jumpDone();
      return;
    }
    SettingsManager.jumpDone();
    const row = jump.row ? card.rowItem(jump.row) : null;
    if (row && row.visible) {
      titledCard.scrollTo(row, true);
      row.flash();
    } else {
      titledCard.scrollTo(card);
      card.flash();
    }
  }

  // Pages the category links to that lead anywhere
  readonly property var links: root.listing ? [] : (root.category?.links ?? []).filter(link => OverlayManager.pageLinkAvailable(link))

  // The category's place in the sidebar (-1 while searching): a new one
  // slides in from the side of the list it was picked from
  readonly property int _pageIndex: root.listing ? -1 : root.categories.indexOf(root.category)
  property int _lastPageIndex: -1

  on_PageIndexChanged: {
    slide.from = (root._pageIndex > root._lastPageIndex ? 1 : -1) * Widget.spacing * 4;
    root._lastPageIndex = root._pageIndex;
    pageIn.restart();
  }

  ParallelAnimation {
    id: pageIn

    NumberAnimation {
      id: slide
      target: pageShift
      property: "y"
      to: 0
      duration: Appearance.animNormal
      easing.type: Easing.OutCubic
    }

    NumberAnimation {
      target: pageBody
      property: "opacity"
      from: 0
      to: 1
      duration: Appearance.animNormal
      easing.type: Easing.OutCubic
    }
  }

  TitledCard {
    id: titledCard
    // I18n.tr("Search results"); category names come from the schema's
    // x-categories
    // Each category keeps its own place; search results start at the top
    scrollKey: root.listing ? "" : "Settings/" + (root.category?.name ?? "")
    // I18n.tr("Changed from default")
    title: root.searching ? I18n.tr("Search results") : SettingsManager.changedOnly ? I18n.tr("Changed from default") : (root.category ? I18n.tr(root.category.name) : "")
    dirty: SettingsManager.isDirty
    onSave: SettingsManager.saveChanges()
    onReset: SettingsManager.resetChanges()

    // Fold all on the left, links to other pages on the right
    showExtras: root.links.length > 0 || root.foldableKeys.length > 0
    headerExtras: RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing

      StyledTextButton {
        visible: root.foldableKeys.length > 0
        Layout.preferredHeight: Widget.height - Widget.px(4)
        text: root.allFolded ? I18n.tr("Unfold all") : I18n.tr("Fold all")
        iconText: root.allFolded ? "unfold_more" : "unfold_less"
        onClicked: root.setAllFolded(!root.allFolded)
      }

      Item {
        Layout.fillWidth: true
      }

      StyledText {
        visible: root.links.length > 0
        text: I18n.tr("More in")
        opacity: 0.6
      }

      Repeater {
        model: root.links

        delegate: StyledTextButton {
          required property string modelData
          Layout.preferredHeight: Widget.height - Widget.px(4)
          text: OverlayManager.pageLinkLabel(modelData)
          iconText: OverlayManager.pageLinkIcon(modelData)
          onClicked: OverlayManager.followPageLink(modelData)
        }
      }
    }

    // The page, which moves as one when it changes
    ColumnLayout {
      id: pageBody
      Layout.fillWidth: true
      spacing: Widget.spacing * 2
      transform: Translate {
        id: pageShift
      }

      StyledText {
        wrapMode: Text.WordWrap
        visible: root.listing && root.groups.length === 0
        text: root.searching ? I18n.tr("No settings match \"{0}\"", SettingsManager.query) : I18n.tr("Every setting is at its default")
        opacity: 0.6
        Layout.fillWidth: true
        Layout.topMargin: Widget.padding
      }

      Repeater {
        id: blocksRepeater
        model: root.blocks

        delegate: ColumnLayout {
          id: block
          required property var modelData
          Layout.fillWidth: true
          spacing: Widget.spacing

          readonly property real gap: Widget.spacing * 2
          // Each card's measured height, by index
          property var heights: block.modelData.groups.map(() => 0)
          // Which cards span both columns (from the schema only)
          readonly property var wide: block.modelData.groups.map(group => group.wide === true)
          // Each run's split, between the wide cards
          property var splits: []
          property bool settling: true
          readonly property var placed: ColumnSplit.place(block.heights, block.wide, block.splits, block.gap)

          function setHeight(i, height) {
            if (block.heights[i] === height)
              return;
            const next = block.heights.slice();
            next[i] = height;
            block.heights = next;
            if (block.settling) {
              block.splits = ColumnSplit.splits(next, block.wide, block.gap);
              settle.restart();
            }
          }

          function relayout() {
            block.settling = true;
            block.splits = ColumnSplit.splits(block.heights, block.wide, block.gap);
            settle.restart();
          }

          // Fixes `splits` once the heights stop changing (cards loading or
          // folding): a quiet spell, restarted by every change, so not an
          // animation duration (which is 0 with motion off)
          Timer {
            id: settle
            interval: 150
            running: true
            onTriggered: {
              block.settling = false;
              root._takeJump();
            }
          }

          Connections {
            target: root
            function onRelayout() {
              block.relayout();
            }
          }

          // A search result's category: its icon and name, then a rule.
          // Names come from the schema's x-categories
          RowLayout {
            visible: block.modelData.name !== ""
            Layout.fillWidth: true
            Layout.topMargin: Widget.spacing
            spacing: Widget.spacing

            StyledIcon {
              text: block.modelData.icon
              textColor: Theme.accent
            }

            StyledText {
              text: I18n.tr(block.modelData.name)
              textSize: Appearance.fontSizeBy(2)
              font.bold: true
            }

            StyledSeparator {
              Layout.fillWidth: true
              separatorHeight: 1
              opacity: 0.3
            }
          }

          // The block's cards, each run between wide ones split in two
          // columns. Positions follow the cards' heights live; `splits`
          // follow them only while `settling` (after a build, a resize or
          // fold all)
          Item {
            id: cards
            Layout.fillWidth: true
            implicitHeight: block.placed.height
            onWidthChanged: block.relayout()

            Repeater {
              model: block.modelData.groups

              // A hand-built card (`x-card`: settings/<name>Card.qml) or rows,
              // streamed in on opening a category or on a search (one letter
              // matches most of the page), the ones in view first
              delegate: StreamedLoader {
                id: card
                always: true
                label: `settings card ${card.modelData.key}`
                required property var modelData
                required property int index
                readonly property var place: block.placed.cards[card.index] ?? ({
                    "column": 0,
                    "y": 0
                  })
                readonly property real halfWidth: (cards.width - block.gap) / 2
                width: card.place.column === -1 ? cards.width : card.halfWidth
                x: card.place.column === 1 ? card.halfWidth + block.gap : 0
                y: card.place.y
                onImplicitHeightChanged: block.setHeight(card.index, card.implicitHeight)
                Component.onCompleted: {
                  if (!root.listing)
                    root._cards[card.modelData.key] = card;
                  // Its title from the schema (`x-cardTitle`, or the
                  // category's `cardTitle`), as the sidebar names it
                  if (card.modelData.kind === "card")
                    card.setSource(Qt.resolvedUrl(card.modelData.card + "Card.qml"), Object.assign({
                      "title": I18n.tr(card.modelData.title)
                    }, card.modelData.folds ? {
                      "foldKey": card.modelData.key
                    } : {}));
                  else
                    card.sourceComponent = rowsCard;
                  block.setHeight(card.index, card.implicitHeight);
                }
                Component.onDestruction: {
                  if (root._cards[card.modelData.key] === card)
                    delete root._cards[card.modelData.key];
                }

                // Its block's columns are still settling: a jump to it
                // waits, or it would scroll to where the card was
                readonly property bool settling: block.settling

                // Outlines the card for a moment (jumped to from the
                // sidebar)
                function flash() {
                  outline.flash();
                }

                // The row showing a setting (a key path), or null
                function rowItem(path) {
                  return card.item?.rowItem?.(path) ?? null;
                }

                FlashOutline {
                  id: outline
                  anchors.fill: parent
                }

                Component {
                  id: rowsCard
                  SettingsGroupCard {
                    group: card.modelData
                    form: root
                    showSection: root.listing
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
