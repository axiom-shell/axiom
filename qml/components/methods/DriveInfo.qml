pragma Singleton
import QtQuick

// What a removable drive shows and does, from the daemon's `drives` state
// (DrivesManager): its name, size and icon, the volumes a list shows
// (an unlocked LUKS container standing for its cleartext volume), each
// volume's main action, the one opening the drive opens, and the ignore
// list's match. The daemon lists an unlocked container's cleartext
// volume only through it (cleartextId; its filesystem, mount points and
// mountable). A drive is { id, vendor, model, size, bus,
// optical, removable, canEject, canPowerOff, volumes }, a volume { id,
// device, label, uuid, fsType, size, mountPoints, readOnly, encrypted,
// unlocked, cleartextId, mountable }.
QtObject {
  id: root

  // A size the way drives are sold, in powers of 1000, one decimal under
  // 10 ("512 MB", "7.8 GB", "32 GB", "2.0 TB"); "" for none
  function size(bytes) {
    let value = Number(bytes) || 0;
    if (value <= 0)
      return "";
    const units = ["B", "kB", "MB", "GB", "TB"];
    let unit = 0;
    while (value >= 1000 && unit < units.length - 1) {
      value /= 1000;
      unit++;
    }
    const shown = unit === 0 || value >= 10 ? String(Math.round(value)) : value.toFixed(1);
    return shown + " " + units[unit];
  }

  // The drive's name: its one labelled volume's label, else its vendor
  // and model; "" when it has none (the caller says "Drive")
  function name(drive) {
    if (!drive)
      return "";
    const labels = root.volumes(drive).map(v => v.label).filter(l => !!l);
    if (labels.length === 1)
      return labels[0];
    return [drive.vendor ?? "", drive.model ?? ""].map(s => String(s).trim()).filter(s => s !== "").join(" ");
  }

  // Its vendor and model, when the name is something else (a label); else
  // ""
  function hardware(drive) {
    const hw = [drive?.vendor ?? "", drive?.model ?? ""].map(s => String(s).trim()).filter(s => s !== "").join(" ");
    return hw !== root.name(drive) ? hw : "";
  }

  // "SanDisk Ultra · 32 GB": the name, and the size when known
  function displayName(drive, fallback) {
    const parts = [root.name(drive) || (fallback ?? ""), root.size(drive?.size)].filter(s => s !== "");
    return parts.join(" · ");
  }

  // A Material Symbols icon: a disc, a memory card, a USB stick, else a
  // drive
  function icon(drive) {
    if (drive?.optical)
      return "album";
    if (drive?.bus === "sdio" || /\b(SD|MMC|card)\b/i.test(drive?.model ?? ""))
      return "sd_card";
    if (drive?.bus === "usb")
      return "usb";
    return "hard_drive";
  }

  // The volumes a list shows: those that can be mounted or unlocked
  function volumes(drive) {
    return (drive?.volumes ?? []).filter(v => v.mountable || v.encrypted);
  }

  // The volume a shown one acts as: an unlocked container's cleartext
  // volume (the container's filesystem, mount points and mountable under
  // the cleartext's id), else itself
  function effective(volume) {
    if (!volume?.encrypted || !volume.unlocked || !volume.cleartextId)
      return volume ?? null;
    return {
      "id": volume.cleartextId,
      "label": volume.label,
      "fsType": volume.fsType,
      "size": volume.size,
      "mountPoints": volume.mountPoints ?? [],
      "mountable": volume.mountable === true,
      "encrypted": false
    };
  }

  // A volume is mounted somewhere
  function mounted(volume) {
    return (volume?.mountPoints ?? []).length > 0;
  }

  // Locked: an encrypted volume not unlocked
  function locked(volume) {
    return volume?.encrypted === true && volume.unlocked !== true;
  }

  // What clicking a shown volume does: "unlock" (locked), "open"
  // (mounted), "mount", else "" (nothing to mount)
  function action(volume) {
    if (root.locked(volume))
      return "unlock";
    const v = root.effective(volume);
    if (root.mounted(v))
      return "open";
    return v?.mountable ? "mount" : "";
  }

  // Any shown volume is mounted
  function driveMounted(drive) {
    return root.volumes(drive).some(v => root.mounted(root.effective(v)));
  }

  // The ids of the drive's mounted shown volumes, with those of `before`
  // (its ids as last seen) whose volume is gone from it: a pulled drive's
  // volumes leave udisks before the drive does, still mounted
  function mountedIds(drive, before) {
    const shown = root.volumes(drive);
    const ids = shown.map(v => v.id);
    const now = shown.filter(v => root.mounted(root.effective(v))).map(v => v.id);
    return now.concat((before ?? []).filter(id => !ids.includes(id) && !now.includes(id)));
  }

  // Any shown volume is locked
  function driveLocked(drive) {
    return root.volumes(drive).some(v => root.locked(v));
  }

  // The first mount point of the drive's volumes, else ""
  function mountPoint(drive) {
    for (const v of root.volumes(drive)) {
      const points = root.effective(v)?.mountPoints ?? [];
      if (points.length > 0)
        return points[0];
    }
    return "";
  }

  // The shown volume opening the drive acts on: { volume, action } for
  // the first one mounted, else to mount, else to unlock; null with none
  function pick(drive) {
    const shown = root.volumes(drive);
    for (const wanted of ["open", "mount", "unlock"]) {
      const volume = shown.find(v => root.action(v) === wanted);
      if (volume)
        return {
          "volume": volume,
          "action": wanted
        };
    }
    return null;
  }

  // What a click on a drive event (an OSD card, a notification) does:
  // "open" its folder (mounted), "unlock" it (an encrypted drive
  // plugged in), else "show" the Drives module
  function clickAction(kind) {
    switch (kind) {
    case "mounted":
      return "open";
    case "locked":
      return "unlock";
    }
    return "show";
  }

  // The drive matches an ignore list entry (Drives.ignore): a volume's
  // UUID or label, exactly
  function ignored(drive, list) {
    const entries = (list ?? []).filter(e => e !== "");
    if (!drive || entries.length === 0)
      return false;
    const keys = [];
    (drive.volumes ?? []).forEach(v => keys.push(v.uuid ?? "", v.label ?? ""));
    return keys.some(k => k !== "" && entries.includes(k));
  }
}
