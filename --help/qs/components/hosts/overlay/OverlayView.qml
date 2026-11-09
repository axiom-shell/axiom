pragma ComponentBehavior: Bound
import QtQuick

// Loads one overlay page (views/<type>.qml) for OverlayPages, keeping its
// grid and viewConfig bound so config edits reach it.
Item {
  id: root
  required property OverlayGrid grid
  // { component, viewConfig } from OverlayPages.buildViewsModel
  required property var viewModel

  implicitWidth: viewLoader.item ? viewLoader.item.implicitWidth : 0
  implicitHeight: viewLoader.item ? viewLoader.item.implicitHeight : 0

  // Created with its inputs already set, then bound so config edits reach it
  function _load() {
    viewLoader.setSource(root.viewModel.component, {
      "grid": root.grid,
      "viewConfig": root.viewModel.viewConfig
    });
  }
  Component.onCompleted: _load()

  Loader {
    id: viewLoader
    anchors.centerIn: parent
    onLoaded: {
      item.grid = Qt.binding(() => root.grid);
      item.viewConfig = Qt.binding(() => root.viewModel.viewConfig);
    }
  }
}
