pragma Singleton
import QtQuick

// Where a line of text looks centred: on the band its letters fill, not
// on its line box (ascent + descent), which holds the room for accents
// above and descenders below and so centres lowercase text a pixel or two
// low beside an icon. The band is fixed by the font, never the string's
// ink, so a label doesn't move with its text's descenders or capitals,
// only (by half the two bands' difference) when lowercase comes or goes
// from it: the x-height for text
// with lowercase in it (whose middle is also the middle of its ascenders
// over its descenders), a figure's height (a digit's, as tall as a
// capital) for text without (numbers, capitals). TextBandPadding pads a
// Text by it, for anything placing that Text by its box.
QtObject {
  id: root

  // Whether `text` (plain) centres on the x-height: it has a lowercase
  // letter. Capitals, figures, symbols and scripts without case centre
  // on a figure's height
  function onXHeight(text) {
    return text !== text.toUpperCase();
  }

  // The band's height for `text`, given the font's `xHeight` and
  // `figureHeight` (an "x"'s and a "0"'s ink heights)
  function height(text, xHeight, figureHeight) {
    return root.onXHeight(text) ? xHeight : figureHeight;
  }

  // { top, bottom }: the padding (≥ 0, one side 0) that puts a Text's box's
  // middle on the band's middle, for a line `contentHeight` high (the
  // Text's, padding left out) with its baseline `ascent` below its top and
  // the band `band` high above the baseline
  function padding(ascent, contentHeight, band) {
    // How much further the band's middle is from the top than from the
    // bottom
    const over = 2 * ascent - contentHeight - band;
    return {
      "top": Math.max(0, -over),
      "bottom": Math.max(0, over)
    };
  }
}
