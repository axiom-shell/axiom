.pragma library
// The OSD's timelines (tst_OSDSystems runs them): one file of rows per
// system, by its name, and Cross for rows across systems. A file whose
// system has no folder yet is skipped, visibly. The row format is
// docs/dev/features/osd.md › Engine › Timelines.
.import "Audio.js" as Audio
.import "Brightness.js" as Brightness
.import "LockKeys.js" as LockKeys
.import "KeyboardLayout.js" as KeyboardLayout
.import "Privacy.js" as Privacy
.import "Bluetooth.js" as Bluetooth
.import "Wifi.js" as Wifi
.import "Airplane.js" as Airplane
.import "Vpn.js" as Vpn
.import "Battery.js" as Battery
.import "PowerProfile.js" as PowerProfile
.import "Caffeine.js" as Caffeine
.import "Dnd.js" as Dnd
.import "NightLight.js" as NightLight
.import "Recording.js" as Recording
.import "Drives.js" as Drives
.import "Monitors.js" as Monitors
.import "Screenshot.js" as Screenshot
.import "Message.js" as Message
.import "Media.js" as Media
.import "Cross.js" as Cross

var files = {
  "Audio": Audio.rows,
  "Brightness": Brightness.rows,
  "LockKeys": LockKeys.rows,
  "KeyboardLayout": KeyboardLayout.rows,
  "Privacy": Privacy.rows,
  "Bluetooth": Bluetooth.rows,
  "Wifi": Wifi.rows,
  "Airplane": Airplane.rows,
  "Vpn": Vpn.rows,
  "Battery": Battery.rows,
  "PowerProfile": PowerProfile.rows,
  "Caffeine": Caffeine.rows,
  "Dnd": Dnd.rows,
  "NightLight": NightLight.rows,
  "Recording": Recording.rows,
  "Drives": Drives.rows,
  "Monitors": Monitors.rows,
  "Screenshot": Screenshot.rows,
  "Message": Message.rows,
  "Media": Media.rows,
  "Cross": Cross.rows
};
