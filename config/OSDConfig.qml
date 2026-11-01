pragma Singleton
import QtQuick
import qs.services.core

// Reader for the OSD section (the on-screen displays of levels, lock keys,
// the keyboard layout, toggles and the track). Named OSDConfig because
// `OSD` is the module type.
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.OSD

  // Level change per wheel notch (0-1); 0 when scrolling is off
  readonly property real scrollStep: _c.scrollToChange ? _c.scrollStep / 100 : 0
  // [OSDEntry] (see the schema): each with its id, screen (a ScreenTarget),
  // place, `bars` (their layout and items, { type, icon, showOsd, … }),
  // `statuses` ({ row, items, quiet }: the status types shown as icons)
  // and `media` (the now playing card). Goes through a string so a reload
  // that leaves the list unchanged doesn't rebuild the OSDs.
  readonly property string _osdsJson: JSON.stringify(_c.items)
  readonly property var osds: JSON.parse(_osdsJson)
  // The enabled ones, by id: what the shell builds
  readonly property var shownIds: osds.filter(osd => osd.enabled).map(osd => osd.id)
  // The streams the App bars of every OSD match, which the Other apps bars
  // skip
  readonly property var excludedApps: [].concat(...osds.map(osd => [].concat(...osd.bars.items.filter(item => item.type === "app").map(item => item.apps))))

  function osdById(id) {
    return osds.find(osd => osd.id === id) ?? null;
  }

  // The OSD a message goes to (`axiom ipc osd message`): the enabled one
  // of that id, else the first enabled one with a Messages item, else the
  // first enabled one; "" with none
  function messageOsd(id) {
    const shown = osds.filter(osd => osd.enabled);
    const pick = shown.find(osd => osd.id === id) ?? shown.find(osd => osd.statuses.items.includes("message")) ?? shown[0];
    return pick ? pick.id : "";
  }

  // A bar's or status type's name, translated
  function nameOf(type) {
    // I18n.tr("System volume") I18n.tr("Other apps") I18n.tr("Microphone") I18n.tr("Brightness")
    // I18n.tr("Caps Lock") I18n.tr("Num Lock") I18n.tr("Scroll Lock") I18n.tr("Keyboard layout")
    // I18n.tr("Microphone muted") I18n.tr("Output device") I18n.tr("Power profile") I18n.tr("Caffeine")
    // I18n.tr("Do not disturb") I18n.tr("Night light") I18n.tr("Wi-Fi") I18n.tr("Bluetooth")
    // I18n.tr("Airplane mode") I18n.tr("Charger") I18n.tr("Messages")
    const names = {
      "master": "System volume",
      "other": "Other apps",
      "microphone": "Microphone",
      "brightness": "Brightness",
      "capsLock": "Caps Lock",
      "numLock": "Num Lock",
      "scrollLock": "Scroll Lock",
      "keyboardLayout": "Keyboard layout",
      "micMute": "Microphone muted",
      "outputDevice": "Output device",
      "powerProfile": "Power profile",
      "caffeine": "Caffeine",
      "dnd": "Do not disturb",
      "nightLight": "Night light",
      "wifi": "Wi-Fi",
      "bluetooth": "Bluetooth",
      "airplane": "Airplane mode",
      "charger": "Charger",
      "message": "Messages"
    };
    return names[type] ? I18n.tr(names[type]) : "";
  }

  // The name on its tab: its own, else its bars', else its status icons'
  // (so the default isn't named by all of them), else Now playing
  function labelOf(osd) {
    if (osd.name)
      return osd.name;
    const bars = osd.bars.items.map(item => item.type === "app" ? (item.apps.join(" / ") || I18n.tr("An app")) : root.nameOf(item.type));
    const parts = bars.length > 0 ? bars : osd.statuses.items.map(type => root.nameOf(type)).filter(name => name !== "");
    if (parts.length > 0)
      return parts.join(", ");
    return osd.media.enabled ? I18n.tr("Now playing") : I18n.tr("Empty OSD");
  }
}
