pragma Singleton
import QtQuick

// Audio devices as axiom names them (AudioManager.deviceLabel: the OSD's
// device tiles and cards, the Audio widgets): a PipeWire node's name and
// profile, from its properties.
QtObject {
  id: root

  // An audio device's name as shown (AudioManager.deviceLabel), from its
  // PipeWire node ({ nick: node.nick, description: node.description, profile:
  // device.profile.description, bus: device.bus, kind: deviceKind's }):
  // { title, detail }. The nick names the device ("AudioBox Go", a
  // monitor's model, a headset's alias) unless it's a sound chip's
  // generic one; else the description without the profile it ends with
  // (a virtual device's own name); a built-in sound chip's description
  // names the chip, not what's plugged in, so it's the kind's. `detail`
  // the profile ("Analog Stereo"), unless the title is the description.
  // I18n.tr("Speakers") I18n.tr("Headphones") I18n.tr("Headset") I18n.tr("Display") I18n.tr("Webcam") I18n.tr("Bluetooth")
  function deviceName(d) {
    const nick = String(d?.nick ?? "").trim();
    const profile = String(d?.profile ?? "").trim();
    let description = String(d?.description ?? "").trim();
    const generic = nick === "" || /^(HD-Audio Generic|HDA\b)/i.test(nick);
    if (!generic)
      return {
        "title": nick,
        "detail": profile
      };
    if (description !== "" && d?.bus !== "pci") {
      description = description.replace(/\s*\[[^\]]*\]$/, "");
      if (profile !== "" && description.endsWith(" " + profile))
        return {
          "title": description.slice(0, -profile.length - 1),
          "detail": profile
        };
      return {
        "title": description,
        "detail": ""
      };
    }
    const labels = {
      "speaker": "Speakers",
      "headphones": "Headphones",
      "headset": "Headset",
      "hdmi": "Display",
      "webcam": "Webcam",
      "bluetooth": "Bluetooth"
    };
    return {
      "title": labels[d?.kind] ?? labels.speaker,
      "detail": profile,
      "translate": true
    };
  }
}
