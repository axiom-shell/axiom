pragma ComponentBehavior: Bound
import QtQuick
import qs.services.session
import qs.services.ui
import qs.components.reusable
import qs.components.views.base

// The layouts editor: always the last page (pinned by OverlayPages; not
// part of config). The overlay pages, edge menus, the desktop, the lock
// screen and the login screen on the left; the selected one's modules on a
// canvas (drag to move, drag a corner to resize) above the selected
// module's options, or the library to add from. Edits go through
// OverlayManager's (pages and menus), DesktopManager's, LockManager's and
// GreeterManager's drafts until saved; a menu's and the desktop's show
// live on screen.
BaseView {
  id: root

  // What's being edited (OverlayManager.editTarget), as the canvas shows it
  readonly property EditTarget target: OverlayManager.editTarget === "menu" ? menuTarget : OverlayManager.editTarget === "desktop" ? desktopTarget : OverlayManager.editTarget === "lockscreen" ? lockscreenTarget : OverlayManager.editTarget === "greeter" ? greeterTarget : pageTarget

  PageTarget {
    id: pageTarget
  }
  MenuTarget {
    id: menuTarget
  }
  DesktopTarget {
    id: desktopTarget
  }
  LockscreenTarget {
    id: lockscreenTarget
  }
  GreeterTarget {
    id: greeterTarget
  }

  Component.onCompleted: {
    OverlayManager.ensureLoaded();
    OverlayManager.menus.ensureLoaded();
    DesktopManager.editor.ensureLoaded();
    LockManager.editor.ensureLoaded();
    GreeterManager.editor.ensureLoaded();
  }
  // The page unloads when the overlay closes (or it pages two away)
  Component.onDestruction: OverlayManager.menus.stopPreviewing()

  LayoutsEditorLayout {
    id: layout
    grid: root.grid
    mainWidth: root.editorWidth
    editor: root.target.editor
    canvas.modules: root.target.modules
    canvas.icon: root.target.icon
    canvas.title: root.target.title
    canvas.emptyText: root.target.emptyText
    canvas.edge: root.target.edge
    canvas.screenBox: root.target.screenBox
    canvas.screenSize: root.target.screenSize
    canvas.reservedDepth: root.target.reservedDepth
    canvas.reservedLabel: root.target.reservedLabel
    canvas.ghosts: root.target.ghosts
    canvas.fitText: root.target.fitText
    canvas.fitWarning: root.target.fitWarning
    canvas.fitLink: root.target.fitLink
    canvas.nudgeText: root.target.nudgeText
    canvas.nudgeVertical: root.target.nudgeVertical
    canvas.canNudgeBack: root.target.canNudgeBack
    canvas.canNudgeForward: root.target.canNudgeForward
    canvas.canCentre: root.target.canCentre
    canvas.nudge: root.target.nudge
    canvas.centre: root.target.centre
    canvas.gridOffset: root.target.gridOffset
    canvas.gridOffsetLimit: root.target.gridOffsetLimit
    canvas.setGridOffset: root.target.setGridOffset
    canvas.latticeSpan: root.target.latticeSpan
    canvas.dirty: OverlayManager.isDirty || OverlayManager.menus.isDirty || DesktopManager.editor.isDirty || LockManager.editor.isDirty || GreeterManager.editor.isDirty
    canvas.canSave: OverlayManager.problems.length === 0 && OverlayManager.menus.problems.length === 0 && DesktopManager.editor.problems.length === 0 && LockManager.editor.problems.length === 0 && GreeterManager.editor.problems.length === 0
    inspector.editable: root.target.editable
    inspector.notEditableHint: root.target.notEditableHint
    onSave: {
      if (OverlayManager.isDirty)
        OverlayManager.saveChanges();
      if (OverlayManager.menus.isDirty)
        OverlayManager.menus.saveChanges();
      if (DesktopManager.editor.isDirty)
        DesktopManager.editor.saveChanges();
      if (LockManager.editor.isDirty)
        LockManager.editor.saveChanges();
      if (GreeterManager.editor.isDirty)
        GreeterManager.editor.saveChanges();
    }
    onReset: {
      OverlayManager.resetChanges();
      OverlayManager.menus.resetChanges();
      DesktopManager.editor.resetChanges();
      LockManager.editor.resetChanges();
      GreeterManager.editor.resetChanges();
    }

    // Streamed in a moment after the page (StreamedLoader), at its size
    StreamedLoader {
      width: layout.sideWidth
      height: layout.pageHeight
      label: "layouts panel"

      sourceComponent: LayoutsPanel {
        view: OverlayManager.editTarget === "page" ? pageTarget.view : null
        menu: OverlayManager.editTarget === "menu" ? menuTarget.menu : null
        screenTarget: OverlayManager.editTarget === "desktop" ? desktopTarget : OverlayManager.editTarget === "lockscreen" ? lockscreenTarget : OverlayManager.editTarget === "greeter" ? greeterTarget : null
        dragLayer: layout
      }
    }
  }
}
