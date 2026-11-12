import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "BarAutoColors"

  readonly property var accents: [
    {
      "name": "red",
      "color": "#e06c75"
    },
    {
      "name": "orange",
      "color": "#d19a66"
    },
    {
      "name": "yellow",
      "color": "#e5c07b"
    },
    {
      "name": "green",
      "color": "#98c379"
    },
    {
      "name": "blue",
      "color": "#61afef"
    }
  ]

  function palette(overrides = {}) {
    return Object.assign({
      "accents": accents,
      "neutrals": [
        {
          "name": "n1",
          "color": "#21252b"
        },
        {
          "name": "n2",
          "color": "#3e4451"
        },
        {
          "name": "n3",
          "color": "#7f848e"
        }
      ],
      "warning": accents[2],
      "critical": accents[0],
      "rise": accents[1],
      "fall": accents[0],
      "backdrop": "#1e2127",
      "minContrast": 1.3
    }, overrides);
  }

  function widget(roles = {
    "backgroundColor": "accent"
  }, set = {}) {
    return {
      "roles": roles,
      "set": set
    };
  }

  function row(count) {
    return Array.from({
      "length": count
    }, () => widget());
  }

  function test_neighbours_differ() {
    const picks = BarAutoColors.assign(row(12), palette()).map(p => p.backgroundColor);
    for (let i = 1; i < picks.length; i++)
      verify(picks[i] !== picks[i - 1], `${i}: ${picks}`);
  }

  function test_every_accent_before_a_repeat() {
    const picks = BarAutoColors.assign(row(5), palette()).map(p => p.backgroundColor);
    compare(new Set(picks).size, 5);
  }

  function test_fixed_neighbours_are_avoided() {
    const widgets = [widget({
        "backgroundColor": "accent"
      }, {
        "backgroundColor": "#61afef"
      }), widget(), widget({
        "backgroundColor": "accent"
      }, {
        "backgroundColor": "#e06c75"
      })];
    const picks = BarAutoColors.assign(widgets, palette());
    compare(Object.keys(picks[0]).length, 0);
    verify(!["blue", "red"].includes(picks[1].backgroundColor), picks[1].backgroundColor);
  }

  function test_widgets_without_auto_fields_are_skipped() {
    const widgets = [widget(), widget({}), widget()];
    const picks = BarAutoColors.assign(widgets, palette());
    compare(Object.keys(picks[1]).length, 0);
    verify(picks[0].backgroundColor !== picks[2].backgroundColor);
  }

  function test_low_contrast_accents_are_skipped() {
    const dim = accents.concat([
      {
        "name": "dim",
        "color": "#22252b"
      }
    ]);
    const picks = BarAutoColors.assign(row(12), palette({
      "accents": dim,
      "minContrast": 3
    })).map(p => p.backgroundColor);
    verify(!picks.includes("dim"), picks);
  }

  function test_too_few_usable_falls_back_to_the_most_contrasting() {
    const picks = BarAutoColors.assign(row(6), palette({
      "minContrast": 21
    })).map(p => p.backgroundColor);
    compare(new Set(picks).size, 3);
  }

  function test_alt_differs_from_the_accent() {
    const picks = BarAutoColors.assign([widget({
        "backgroundColor": "accent",
        "connectedColor": "alt"
      })], palette());
    verify(picks[0].connectedColor !== picks[0].backgroundColor);
  }

  function test_states_take_the_palette_and_stay_apart_from_the_accent() {
    const picks = BarAutoColors.assign(row(4).map(() => widget({
        "backgroundColor": "accent",
        "lowColor": "warning",
        "criticalColor": "critical"
      })), palette());
    picks.forEach(p => {
      compare(p.lowColor, "yellow");
      compare(p.criticalColor, "red");
      verify(!["yellow", "red"].includes(p.backgroundColor), p.backgroundColor);
    });
  }

  function test_rise_and_fall_take_the_palettes() {
    const picks = BarAutoColors.assign([widget({
        "backgroundColor": "accent",
        "upColor": "rise",
        "downColor": "fall"
      })], palette());
    compare(picks[0].upColor, accents[1].name);
    compare(picks[0].downColor, accents[0].name);
    verify(![picks[0].upColor, picks[0].downColor].includes(picks[0].backgroundColor), "the accent stays unlike them");
  }

  function test_off_is_the_subtlest_neutral_that_shows() {
    const roles = {
      "backgroundColor": "accent",
      "mutedColor": "off"
    };
    compare(BarAutoColors.assign([widget(roles)], palette())[0].mutedColor, "n2");
    compare(BarAutoColors.assign([widget(roles)], palette({
      "minContrast": 3
    }))[0].mutedColor, "n3");
  }

  // A box for colorful content (the tray) takes a neutral, not an accent
  function test_neutral_box() {
    const picks = BarAutoColors.assign([widget({
        "backgroundColor": "neutral"
      })], palette());
    compare(picks[0].backgroundColor, "n2");
  }

  function test_fixed_fields_are_left_alone() {
    const picks = BarAutoColors.assign([widget({
        "backgroundColor": "accent",
        "mutedColor": "off"
      }, {
        "mutedColor": "#ffffff"
      })], palette());
    verify(!("mutedColor" in picks[0]));
  }

  function test_stable() {
    compare(JSON.stringify(BarAutoColors.assign(row(9), palette())), JSON.stringify(BarAutoColors.assign(row(9), palette())));
  }
}
