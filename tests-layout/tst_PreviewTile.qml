import QtQuick
import QtTest
import qs.config
import qs.components.reusable

// PreviewTile's preview look (the layout harness): titles are plain text, a
// caption reserves its lines so tiles in a row stay even, and a click on the
// caption is a click on the tile.
TestCase {
  id: root

  name: "PreviewTile"
  when: windowShown
  visible: true
  width: 600
  height: 400

  Harness {
    id: harness
  }

  Component {
    id: tileComp

    PreviewTile {
      width: 200
      title: "Name"
      previewHeight: 60
    }
  }

  function init() {
    harness.configure({});
  }

  function findAll(item, pred) {
    const out = [];
    const walk = it => {
      if (pred(it))
        out.push(it);
      for (const child of it.children)
        walk(child);
    };
    walk(item);
    return out;
  }

  function test_titles_are_plain_text() {
    const tile = createTemporaryObject(tileComp, root, {
      "title": "<b>x</b>"
    });
    const labels = findAll(tile, it => it.text === "<b>x</b>");
    verify(labels.length > 0);
    for (const label of labels)
      compare(label.textFormat, Text.PlainText);
  }

  function test_caption_reserves_its_lines() {
    const bare = createTemporaryObject(tileComp, root);
    const short = createTemporaryObject(tileComp, root, {
      "caption": "Short"
    });
    const long = createTemporaryObject(tileComp, root, {
      "caption": "A long caption that wraps over a good many lines in a narrow tile, well past two"
    });
    verify(short.implicitHeight > bare.implicitHeight, "the caption adds its lines");
    compare(short.implicitHeight, long.implicitHeight, "tiles in a row stay even");
    compare(long.captionRoom, short.captionRoom);
  }

  function test_click_on_the_caption_clicks_the_tile() {
    const tile = createTemporaryObject(tileComp, root, {
      "caption": "Caption"
    });
    waitForRendering(tile);
    let clicks = 0;
    tile.clicked.connect(() => clicks++);
    mouseClick(tile, tile.width / 2, tile.height - 4);
    compare(clicks, 1);
  }
}
