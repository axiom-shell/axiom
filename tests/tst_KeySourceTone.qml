import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "KeySourceTone"

  // Each source's tone is what KeyMapPanel and KeyboardReference gave before
  // they shared it (the reference never meets "paused": KeyMap.labels yields
  // axiom, both and user only)
  function test_tone_data() {
    return [
      {
        "source": "axiom",
        "tone": "accentContainer"
      },
      {
        "source": "both",
        "tone": "errorContainer"
      },
      {
        "source": "paused",
        "tone": "highest"
      },
      {
        "source": "user",
        "tone": "warningContainer"
      },
      {
        "source": "free",
        "tone": "sunken"
      },
      {
        "source": "",
        "tone": "sunken"
      }
    ];
  }

  function test_tone(data) {
    compare(KeySourceTone.tone(data.source), data.tone);
  }
}
