pragma Singleton
import QtQuick
import qs.services.core

// Reader for the ThemeIntegrations section: one switch per
// scripts/theme_<key>.sh, run by ThemeManager.themeIntegrations().
QtObject {
  readonly property var _c: ConfigManager.config.ThemeIntegrations

  readonly property bool gtk: _c.gtk
  readonly property bool qt: _c.qt
  readonly property bool kitty: _c.kitty
  readonly property bool alacritty: _c.alacritty
  readonly property bool foot: _c.foot
  readonly property bool wezterm: _c.wezterm
  readonly property bool ghostty: _c.ghostty
  readonly property bool nvim: _c.nvim
  readonly property bool helix: _c.helix
  readonly property bool vscode: _c.vscode
  readonly property bool zed: _c.zed
  readonly property bool vesktop: _c.vesktop
  readonly property bool firefox: _c.firefox
  readonly property bool k9s: _c.k9s
  readonly property bool cava: _c.cava
  readonly property bool btop: _c.btop
  readonly property bool ncspot: _c.ncspot
  readonly property bool fzf: _c.fzf
  readonly property bool lazygit: _c.lazygit
  readonly property bool bat: _c.bat
  readonly property bool yazi: _c.yazi
  readonly property bool zathura: _c.zathura
}
