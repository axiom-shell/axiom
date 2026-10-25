pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.services.ui
import qs.components.reusable

// The top of the Translucency card (its `x-intro`): a warning that it's
// experimental, and while the surfaces blur, the blur they get: the
// compositor's one (CompositorManager.blur, as in effect), set by the
// window look's blur part or the user's own config. With its blur off
// nothing blurs, and it offers to set it. Where the compositor can't blur
// behind them, the opacity is greyed out and the surfaces are solid
// (Appearance.surfaceAlpha).
ColumnLayout {
  id: root

  readonly property bool off: !CompositorManager.blur.enabled

  spacing: Widget.spacing

  IssueList {
    issues: [
      {
        "level": "warning",
        "text": I18n.tr("Transparency and blur are highly experimental: expect visual glitches and a performance cost.")
      }
    ]
  }

  RowLayout {
    Layout.fillWidth: true
    // Where the compositor blurs axiom's surfaces (the settings below are
    // hidden elsewhere)
    visible: Appearance.blur && CompositorManager.supports.blur === true
    spacing: Widget.spacing

    StatusChip {
      text: root.off ? I18n.tr("Off") : I18n.tr("Blur")
      color: root.off ? Theme.error : Theme.success
    }

    StyledText {
      Layout.fillWidth: true
      wrapMode: Text.WordWrap
      textColor: root.off ? Theme.error : Theme.foreground
      text: {
        if (root.off)
          return I18n.tr("{0}'s blur is off, so nothing blurs behind the surfaces.", CompositorManager.displayName);
        const strength = I18n.tr("{0}'s blur: size {1}, {2} passes.", CompositorManager.displayName, CompositorManager.blur.size, CompositorManager.blur.passes);
        return strength + " " + (WindowLookConfig.look.blur ? I18n.tr("Set in Compositor → Window look.") : I18n.tr("From your compositor's config."));
      }
    }

    StyledTextButton {
      implicitHeight: Widget.height - Widget.px(4)
      text: root.off && !WindowLookConfig.look.blur ? I18n.tr("Set the compositor's blur") : I18n.tr("Change")
      onClicked: {
        if (root.off && !WindowLookConfig.look.blur)
          SettingsManager.setValue(["WindowLook", "blur"], true);
        SettingsManager.openSetting("WindowLook.blur");
      }
    }
  }
}
