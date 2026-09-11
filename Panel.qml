import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// One bar icon, one popup: every drive the user cares about, mounted or not.
// Click the bar icon to open; click a mounted drive to open it in the file
// manager, click an unmounted one to mount it, right-click to unmount.
Panel {
  id: root
  moduleName: "drives"
  ipcTarget: "drives"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color muted: Qt.darker(foreground, 1.45)
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color barFill: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.85)
  readonly property color barTrack: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
  readonly property color barFillWarn: Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal

  // Bar-button glyph: a hard drive outline (FontAwesome regular). The MD
  // harddisk glyph lives at 0xF02CA, but its rendering varies across nerd
  // fonts — the FA version is the most reliable "looks like a drive" icon.
  readonly property string glyph: "\uf0a0"
  readonly property string barTooltip: drives.drives.length === 0
    ? "No drives attached"
    : (drives.busy
        ? "Working — do not remove"
        : drives.drives.length + " drive" + (drives.drives.length === 1 ? "" : "s"))

  function handleBarPress(buttonCode) {
    if (buttonCode === Qt.RightButton) {
      drives.refresh()
    } else if (buttonCode === Qt.MiddleButton) {
      var mounted = drives.drives.filter(function(d) { return d.mounted })
      if (mounted.length > 0) drives.openMountpoint(mounted[0].mountpoint)
    } else {
      toggle()
    }
  }

  function activateDrive(d) {
    if (!d) return
    if (d.mounted) drives.openMountpoint(d.mountpoint)
    else drives.mountDrive(d)
  }

  function formatBytes(bytes) {
    if (!bytes || bytes <= 0) return "0 B"
    var units = ["B", "KiB", "MiB", "GiB", "TiB"]
    var n = bytes
    var u = 0
    while (n >= 1024 && u < units.length - 1) {
      n = n / 1024
      u++
    }
    return n.toFixed(u === 0 ? 0 : 1) + " " + units[u]
  }

  // The Panel's `visible` controls the bar slot. Hide entirely when there
  // is nothing to show, like the working plugin does.
  visible: drives.drives.length > 0
  implicitWidth: button.item ? button.item.implicitWidth : 0
  implicitHeight: button.item ? button.item.implicitHeight : barSize

  onVisibleChanged: if (!visible && opened) close()
  onOpenedChanged: if (opened) {
    drives.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: drives
    settings: root.settings
  }

  // Single bar button. Always icon-only — labels would crowd the bar.
  Loader {
    id: button
    anchors.fill: parent
    sourceComponent: BarIconButton {
      bar: root.bar
      text: root.glyph
      tooltipText: root.barTooltip
      active: drives.busy
      onPressed: function(buttonCode) { root.handleBarPress(buttonCode) }
    }
  }

  // The popup. Anchored on the bar button; clicking outside dismisses.
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(10)

          PanelHero {
            id: hero
            width: parent.width
            title: "Drives"
            meta: drives.drives.length === 0
              ? (drives.loaded ? "Nothing attached" : "Looking for drives…")
              : drives.drives.length + " drive" + (drives.drives.length === 1 ? "" : "s")
                  + " · " + drives.drives.filter(function(d) { return d.mounted }).length + " mounted"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: root.glyph
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              PanelActionButton {
                iconText: "\uf021"  // nf-fa-refresh
                tooltipText: "Rescan"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !drives.refreshing
                onClicked: drives.refresh()
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: drives.lastError !== ""
            width: parent.width
            text: drives.lastError
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: drives.drives

            delegate: Item {
              id: driveRow
              required property var modelData
              required property int index

              width: column.width
              implicitHeight: rowContent.implicitHeight + Style.space(8) * 2

              // Whole-row click target sits at the back, so the action
              // buttons in front of it capture their own clicks first.
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.activateDrive(modelData)
                onPressed: function(m) {
                  if (m.button === Qt.RightButton) {
                    if (modelData.mounted) drives.unmountDrive(modelData)
                    m.accepted = true
                  }
                }
              }

              RowLayout {
                id: rowContent
                anchors.fill: parent
                anchors.margins: Style.space(8)
                spacing: Style.space(8)

                Column {
                  Layout.fillWidth: true
                  spacing: Style.space(4)

                  RowLayout {
                    width: parent.width
                    spacing: Style.space(8)

                    Text {
                      textFormat: Text.PlainText
                      text: modelData.displayLabel
                      color: modelData.mounted ? root.foreground : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: modelData.mounted
                        ? modelData.mountpoint
                        : (modelData.path + " · not mounted")
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideMiddle
                      Layout.maximumWidth: Style.space(180)
                    }
                  }

                  RowLayout {
                    width: parent.width
                    spacing: Style.space(8)

                    Text {
                      textFormat: Text.PlainText
                      text: modelData.mounted
                        ? (root.formatBytes(modelData.usedBytes) + " / " + root.formatBytes(modelData.sizeBytes))
                        : root.formatBytes(modelData.sizeBytes)
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }

                    Text {
                      textFormat: Text.PlainText
                      visible: modelData.mounted
                      text: modelData.percent + "%"
                      color: modelData.percent >= 90 ? Color.urgent : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  // Usage bar. Full-width, low height, the same color rules as
                  // a tray-style widget: dim track, full-color fill, urgent
                  // when the drive is full enough to be worth warning about.
                  Rectangle {
                    width: parent.width
                    Layout.fillWidth: true
                    implicitHeight: Math.max(2, Style.space(3))
                    radius: height / 2
                    color: root.barTrack

                    Rectangle {
                      width: modelData.mounted
                        ? Math.max(parent.width > 0 && modelData.percent > 0 ? 2 : 0,
                                   parent.width * Math.min(100, modelData.percent) / 100)
                        : 0
                      height: parent.height
                      radius: parent.radius
                      color: modelData.percent >= 90 ? root.barFillWarn : root.barFill

                      Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }
                  }
                }

                // Explicit actions on the right edge of the row. They sit on
                // top of the row's MouseArea so clicks land on them, not on
                // the row's open/mount handler. The column is given an
                // explicit width so its buttons line up across rows even
                // when one row only has the mount button (no open button).
                Column {
                  Layout.alignment: Qt.AlignVCenter
                  Layout.preferredWidth: Style.space(72)
                  spacing: Style.space(8)

                  PanelActionButton {
                    width: Style.space(28)
                    height: Style.space(28)
                    // Distinct, unambiguous icons: a plus for mount and an X
                    // for unmount, drawn at the same size so the row stays
                    // balanced. The previous tray_arrow_* pair looked too
                    // similar at a glance.
                    iconText: modelData.mounted ? "\uf00d" : "\uf067"  // fa-close : fa-plus
                    tooltipText: modelData.mounted ? "Unmount " + modelData.displayLabel : "Mount " + modelData.displayLabel
                    foreground: modelData.mounted ? Color.urgent : root.foreground
                    hoverColor: modelData.mounted ? Color.urgent : root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.body
                    bordered: true
                    // Grey out while a mount/unmount on this row is in
                    // flight; the row's text and bar reflect busy state too.
                    enabled: !drives.busy || drives.busyPath !== modelData.path
                    Layout.alignment: Qt.AlignRight
                    onClicked: {
                      if (modelData.mounted) drives.unmountDrive(modelData)
                      else drives.mountDrive(modelData)
                    }
                  }

                  PanelActionButton {
                    visible: modelData.mounted
                    width: Style.space(28)
                    height: Style.space(28)
                    iconText: "\uf07b"  // nf-fa-folder-open
                    tooltipText: "Open " + modelData.mountpoint + " in file manager"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.body
                    bordered: true
                    enabled: !drives.busy
                    Layout.alignment: Qt.AlignRight
                    onClicked: drives.openMountpoint(modelData.mountpoint)
                  }

                  // Spacer so an unmounted row's single button still sits
                  // vertically centered next to a mounted row's two buttons.
                  Item {
                    visible: !modelData.mounted
                    Layout.alignment: Qt.AlignRight
                    Layout.preferredWidth: Style.space(28)
                    Layout.preferredHeight: Style.space(28)
                  }
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: drives.loaded && drives.drives.length === 0
            width: parent.width
            text: "No labeled or mounted drives are visible right now."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}