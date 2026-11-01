pragma Singleton
import QtQuick

// What a removable drive shows and does, from the daemon's `drives` state
// (DrivesManager): its name, size and icon, the volumes a list shows
// (an unlocked LUKS container standing for its cleartext volume), each
// volume's main action, the one opening the drive opens, and the ignore
// list's match. A drive is { id, vendor, model, label, size, bus,
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

  // The drive's name: its own label, else its one labelled volume's, else
  // its vendor and model; "" when it has none (the caller says "Drive")
  function name(drive) {
    if (!drive)
      return "";
    if (drive.label)
      return drive.label;
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

  // The volumes a list shows: those that can be mounted or unlocked,
  // without the cleartext volumes of the drive's own LUKS containers (the
  // container stands for its own)
  function volumes(drive) {
    const all = drive?.volumes ?? [];
    const inner = all.filter(v => v.encrypted && v.cleartextId).map(v => v.cleartextId);
    return all.filter(v => (v.mountable || v.encrypted) && !inner.includes(v.id));
  }

  // The volume a shown one acts as: an unlocked container's cleartext
  // volume, else itself. The daemon reports the cleartext's filesystem
  // and mount points on the container, so when the cleartext isn't
  // listed it's the container's own, under the cleartext's id
  function effective(drive, volume) {
    if (!volume?.encrypted || !volume.unlocked || !volume.cleartextId)
      return volume ?? null;
    return (drive?.volumes ?? []).find(v => v.id === volume.cleartextId) ?? {
      "id": volume.cleartextId,
      "label": volume.label,
      "fsType": volume.fsType,
      "size": volume.size,
      "mountPoints": volume.mountPoints ?? [],
      "mountable": true,
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
  function action(drive, volume) {
    if (root.locked(volume))
      return "unlock";
    const v = root.effective(drive, volume);
    if (root.mounted(v))
      return "open";
    return v?.mountable ? "mount" : "";
  }

  // Any shown volume is mounted
  function driveMounted(drive) {
    return root.volumes(drive).some(v => root.mounted(root.effective(drive, v)));
  }

  // Any shown volume is locked
  function driveLocked(drive) {
    return root.volumes(drive).some(v => root.locked(v));
  }

  // The first mount point of the drive's volumes, else ""
  function mountPoint(drive) {
    for (const v of root.volumes(drive)) {
      const points = root.effective(drive, v)?.mountPoints ?? [];
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
      const volume = shown.find(v => root.action(drive, v) === wanted);
      if (volume)
        return {
          "volume": volume,
          "action": wanted
        };
    }
    return null;
  }

  // The drive matches an ignore list entry (Drives.ignore): a volume's
  // UUID or label, or the drive's label, exactly
  function ignored(drive, list) {
    const entries = (list ?? []).filter(e => e !== "");
    if (!drive || entries.length === 0)
      return false;
    const keys = [drive.label ?? ""];
    (drive.volumes ?? []).forEach(v => keys.push(v.uuid ?? "", v.label ?? ""));
    return keys.some(k => k !== "" && entries.includes(k));
  }
}
