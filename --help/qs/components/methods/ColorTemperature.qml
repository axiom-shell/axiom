pragma Singleton
import QtQuick

// The color of light at a temperature in Kelvin (Tanner Helland's fit to
// blackbody colors), for showing what a night light setting looks like. No
// file access, processes or services.
QtObject {
  id: root

  // { r, g, b } in 0-255 for `kelvin` (clamped to 1000-40000)
  function rgb(kelvin) {
    const t = Math.max(1000, Math.min(40000, kelvin)) / 100;
    const clamp = v => Math.max(0, Math.min(255, Math.round(v)));
    const r = t <= 66 ? 255 : 329.698727446 * Math.pow(t - 60, -0.1332047592);
    const g = t <= 66 ? 99.4708025861 * Math.log(t) - 161.1195681661 : 288.1221695283 * Math.pow(t - 60, -0.0755148492);
    const b = t >= 66 ? 255 : t <= 19 ? 0 : 138.5177312231 * Math.log(t - 10) - 305.0447927307;
    return {
      "r": clamp(r),
      "g": clamp(g),
      "b": clamp(b)
    };
  }

  // The same as a color
  function color(kelvin) {
    const c = rgb(kelvin);
    return Qt.rgba(c.r / 255, c.g / 255, c.b / 255, 1);
  }
}
