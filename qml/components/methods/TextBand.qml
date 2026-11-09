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
// Text by it, for anything placing that Text by its box; the padding keeps
// the Text's size, so no layout grows for it.
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

  // The ascent of a Text's first line as it was laid out, from its
  // `baselineOffset`: less its top padding and how far its vertical
  // alignment moved its lines (`contentHeight` high) down its box (`height`
  // less its paddings). Read off the laid-out line, it's exact where
  // measuring the text isn't: a fallback font's taller ascent (CJK, emoji)
  // moves the baseline down only on the line it's on, and not when it's
  // elided away; Qt lays out some glyphs from a fallback font (Arabic, an
  // icon font's glyph) on the primary font's ascent
  function lineAscent(baselineOffset, topPadding, bottomPadding, height, contentHeight, verticalAlignment) {
    const room = height - topPadding - bottomPadding - contentHeight;
    const moved = verticalAlignment === Text.AlignBottom ? room : verticalAlignment === Text.AlignVCenter ? room / 2 : 0;
    return baselineOffset - topPadding - moved;
  }

  // { top, bottom, offset }: the padding that moves a Text's lines so the
  // middle of its box is the middle of its letters' bands, its size kept
  // (one side the other's negative), for lines `lineHeight` high (one
  // line's height, padding left out) with their baseline `ascent` below
  // their top and the band `band` high above the baseline. Over several
  // lines the first line's band top to the last's baseline is centred,
  // the lines taken as one height (TextBandPadding passes their average,
  // so a fallback font's taller line leaves it a little off).
  // The lines move by whole pixels, as a baseline is drawn on one (moved
  // by a fraction, it would round either way with where the box is):
  // `offset` is what that leaves, how far the band's middle is then below
  // the box's (at most half a pixel), for a host placing the Text itself
  // to take off its position
  function padding(ascent, lineHeight, band) {
    // How far the band's middle is below the box's: the lines move up by
    // that
    const shift = (2 * ascent - lineHeight - band) / 2;
    const whole = Math.round(shift);
    return {
      "top": -whole,
      "bottom": whole,
      "offset": shift - whole
    };
  }
}
