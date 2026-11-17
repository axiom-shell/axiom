pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable

// Where a secret comes from, as a chip: `status` is SecretsManager's (env,
// keyring, file, none, unneeded, else it's still being checked). `envName` is
// the variable an env key comes from; `missingText` is what none says (a key
// or a password).
StatusChip {
  id: root

  property string status: ""
  property string envName: ""
  property string missingText: I18n.tr("No key")

  tone: {
    switch (root.status) {
    case "env":
    case "keyring":
    case "file":
    case "unneeded":
      return "success";
    case "none":
      return "warning";
    }
    return "neutral";
  }
  text: {
    switch (root.status) {
    case "env":
      return I18n.tr("From ${0}", root.envName);
    case "keyring":
      return I18n.tr("In keyring");
    case "file":
      return I18n.tr("In secrets file");
    case "none":
      return root.missingText;
    case "unneeded":
      return I18n.tr("No key needed");
    }
    return I18n.tr("Checking…");
  }
}
