import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar icon for Quick Ask: click (or SUPER+SHIFT+A) opens a centered
// Spotlight-style overlay bound to the system's default agent.
BarWidget {
  id: root
  moduleName: "wolften.quickask"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "wolften.quickask"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    anchors.horizontalCenter: parent.horizontalCenter
    // Optical centering: nerd-font glyphs carry asymmetric side bearings,
    // so the painted glyph sits off the slot center where the bar draws
    // the open-panel dot. Measure the tight bounds at runtime and shift
    // the button so the *painted* center lands on the slot center.
    // (Same math as qs.Ui.OpticalGlyph; vertical bars don't center
    // horizontally, so no shift there.)
    anchors.horizontalCenterOffset: root.vertical ? 0 : root.glyphCenterFix + root.dotCenterShift
    bar: root.bar
    text: "󰚩"
    tooltipText: "Perguntar ao agente (Quick Ask)"
    // Never tint the icon: like the other bar icons, the open state is
    // shown only by the bar's underline dot (popout coordinator).

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        if (root.bar) root.bar.run("omarchy-agent --pick")
      } else {
        root.togglePanel()
      }
    }
  }

  TextMetrics {
    id: glyphMetrics
    font.family: button.fontFamily
    font.pixelSize: Math.max(1, Math.round(button.fontSize))
    text: button.text
  }

  readonly property real glyphCenterFix: {
    var tight = glyphMetrics.tightBoundingRect
    if (!tight || tight.width < 1) return 0
    return glyphMetrics.advanceWidth / 2 - (tight.x + tight.width / 2)
  }

  // The bar's dot is centered with its own rounding (Bar.qml
  // openPanelIndicator), which lands up to half a pixel off the slot
  // center for odd slot widths. Mirror that math so the glyph targets
  // the dot, not the slot.
  readonly property real dotWidth: Math.max(Style.space(10), Math.round(button.implicitWidth * 0.55))
  readonly property real dotCenterShift: Math.round((button.implicitWidth - dotWidth) / 2) + dotWidth / 2 - button.implicitWidth / 2
}
