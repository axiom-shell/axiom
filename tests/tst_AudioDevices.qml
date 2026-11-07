import QtQuick
import QtTest
import qs.components.methods

// AudioDevices: a device's name and profile from its node (moved from
// tst_OSDItems with deviceName)
TestCase {
  name: "AudioDevices"

  function test_deviceName() {
    const rows = [
      // [device, title, detail, translate, what]
      [
        {
          "nick": "CU34G4Z",
          "description": "Navi 31 HDMI/DP Audio Digital Stereo (HDMI) [CU34G4Z]",
          "profile": "Digital Stereo (HDMI)",
          "bus": "pci",
          "kind": "hdmi"
        },
        "CU34G4Z", "Digital Stereo (HDMI)", false, "a monitor by its model"], [
        {
          "nick": "AudioBox Go",
          "description": "AudioBox Go Analog Stereo",
          "profile": "Analog Stereo",
          "bus": "usb",
          "kind": "speaker"
        },
        "AudioBox Go", "Analog Stereo", false, "a USB interface"], [
        {
          "nick": "EMEET SmartCam C960",
          "description": "EMEET SmartCam C960 Mono",
          "profile": "Mono",
          "bus": "usb",
          "kind": "webcam"
        },
        "EMEET SmartCam C960", "Mono", false, "a webcam"], [
        {
          "description": "Easy Effects Sink"
        },
        "Easy Effects Sink", "", false, "a virtual sink"], [
        {
          "nick": "HD-Audio Generic",
          "description": "Family 17h/19h HD Audio Controller Analog Stereo",
          "profile": "Analog Stereo",
          "bus": "pci",
          "kind": "speaker"
        },
        "Speakers", "Analog Stereo", true, "a sound chip: its kind"], [
        {
          "nick": "HD-Audio Generic",
          "description": "Some USB Thing Analog Stereo",
          "profile": "Analog Stereo",
          "bus": "usb",
          "kind": "speaker"
        },
        "Some USB Thing", "Analog Stereo", false, "the description without its profile"], [
        {
          "nick": "WH-1000XM4",
          "description": "WH-1000XM4",
          "profile": "High Fidelity Playback (A2DP Sink)",
          "bus": "bluetooth",
          "kind": "bluetooth"
        },
        "WH-1000XM4", "High Fidelity Playback (A2DP Sink)", false, "a headset by its alias"], [
        {},
        "Speakers", "", true, "nothing known"]];
    for (const [device, title, detail, translate, what] of rows) {
      const name = AudioDevices.deviceName(device);
      compare([name.title, name.detail, name.translate === true], [title, detail, translate], what);
    }
  }
}
