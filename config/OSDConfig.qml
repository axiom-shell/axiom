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

  // A bar's or status type's name, translated: its label in the schema
  // (x-enumLabels of a bar's type and of the statuses)
  readonly property var _typeLabels: {
    const entry = ConfigManager.configSchema?.definitions?.OSDEntry?.properties;
    return Object.assign({}, entry?.bars?.properties?.items?.items?.properties?.type?.["x-enumLabels"], entry?.statuses?.properties?.items?.["x-enumLabels"]);
  }
  function nameOf(type) {
    const english = root._typeLabels[type];
    return english ? I18n.tr(english) : "";
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
