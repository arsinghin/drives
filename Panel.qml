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
  // Theme-composed selection tokens, same pattern as the stock clipboard
  // plugin: a subtle foreground tint over the dark background, and the
  // accent color for the selected row's label.
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color selectedText: Color.menu.selectedText
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  
  // Search and keyboard navigation properties (names must not collide
  // with the base Panel type, which already defines searchText etc.)
  property string driveSearchText: ""
  property int driveSelectedIndex: -1
  property var driveFilteredDrives: []

  Component.onCompleted: {
    updateFilteredDrives(true)
  }

  // resetToTop: true when the result set should highlight its top row
  // (popup open, search text changed); false for background drive-list
  // refreshes so a selection the user is browsing is preserved.
  function updateFilteredDrives(resetToTop) {
    if (!driveSearchText) {
      driveFilteredDrives = drives.drives
    } else {
      var term = driveSearchText.toLowerCase()
      driveFilteredDrives = drives.drives.filter(function(drive) {
        // Search in label, displayLabel, name, and mountpoint
        return (drive.label && drive.label.toLowerCase().includes(term)) ||
               (drive.displayLabel && drive.displayLabel.toLowerCase().includes(term)) ||
               (drive.name && drive.name.toLowerCase().includes(term)) ||
               (drive.mountpoint && drive.mountpoint.toLowerCase().includes(term))
      })
    }
    // Pick the selection: top row by default, previous selection kept
    // while browsing a background refresh, nothing when no results.
    if (driveFilteredDrives.length === 0) {
      driveSelectedIndex = -1
    } else if (resetToTop || driveSelectedIndex < 0 ||
               driveSelectedIndex >= driveFilteredDrives.length) {
      driveSelectedIndex = 0
    }
    scrollToSelected()
  }

  // Keyboard navigation helpers, shared by the key catcher and the
  // search field's own key handlers.
  function navUp() {
    if (driveFilteredDrives.length === 0) return
    driveSelectedIndex = Math.max(0, (driveSelectedIndex < 0 ? 0 : driveSelectedIndex) - 1)
    scrollToSelected()
  }

  function navDown() {
    if (driveFilteredDrives.length === 0) return
    driveSelectedIndex = Math.min(driveFilteredDrives.length - 1,
                                  (driveSelectedIndex < 0 ? -1 : driveSelectedIndex) + 1)
    scrollToSelected()
  }

  function activateSelected() {
    if (driveSelectedIndex >= 0 && driveSelectedIndex < driveFilteredDrives.length) {
      activateDrive(driveFilteredDrives[driveSelectedIndex])
    }
  }

  // Keep the selected row visible in the flickable. Uses the Repeater's
  // itemAt() so we don't need ids from inside the delegate scope.
  function scrollToSelected() {
    if (driveSelectedIndex < 0) return
    Qt.callLater(function() {
      var item = driveRepeater.itemAt(driveSelectedIndex)
      if (!item || panelFlick.contentHeight <= panelFlick.height) return
      var top = item.y
      var bottom = item.y + item.height
      if (top < panelFlick.contentY) {
        panelFlick.contentY = top
      } else if (bottom > panelFlick.contentY + panelFlick.height) {
        panelFlick.contentY = bottom - panelFlick.height
      }
    })
  }

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
    // Dismiss the popup; the action continues in the background.
    close()
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
    // Reset the search box and highlight the top drive right away, so
    // Enter opens it with zero arrow presses.
    root.driveSearchText = ""
    root.updateFilteredDrives(true)
    // Give the popup a moment to lay out, then put the typing pointer in
    // the search box so the user can filter or arrow-navigate immediately.
    searchFocusTimer.restart()
  }

  Timer {
    id: searchFocusTimer
    interval: 60
    repeat: false
    onTriggered: searchField.forceActiveFocus()
  }

  // Re-run the filter whenever the service produces a new drive list, so
  // the popup stays in sync after mounts/unmounts/plug events. Selection
  // is preserved (resetToTop false) so browsing isn't disturbed.
  Connections {
    target: drives
    function onDrivesChanged() {
      root.updateFilteredDrives(false)
    }
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

       Keys.onUpPressed: root.navUp()
       Keys.onDownPressed: root.navDown()
       Keys.onEnterPressed: root.activateSelected()
       Keys.onReturnPressed: root.activateSelected()
       Keys.onEscapePressed: root.close()

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

           // Search box: focused as soon as the popup opens. Typing filters
           // the list live; arrows still move the selection from here.
           TextField {
             id: searchField
             width: parent.width
             placeholderText: "Search drives…"
             text: root.driveSearchText
             color: root.foreground
             font.family: root.fontFamily
             font.pixelSize: Style.font.body
             leftPadding: Style.space(8)
             rightPadding: Style.space(8)
             onTextChanged: {
               root.driveSearchText = text
               root.updateFilteredDrives(true)
             }
             Keys.onUpPressed: root.navUp()
             Keys.onDownPressed: root.navDown()
             Keys.onReturnPressed: root.activateSelected()
             Keys.onEnterPressed: root.activateSelected()
             Keys.onEscapePressed: root.close()
           }

           Repeater {
             id: driveRepeater
             model: root.driveFilteredDrives

delegate: Item {
               id: driveRow
               required property var modelData
               required property int index

width: column.width
               implicitHeight: rowContent.implicitHeight + Style.space(8) * 2
               
               // Selection properties for keyboard navigation
               property int repeaterIndex: index
               property bool isSelected: root.driveSelectedIndex === repeaterIndex

               // Background highlight for selected item
               Rectangle {
                 anchors.fill: parent
                 color: driveRow.isSelected ? root.selectedBackground : "transparent"
                 visible: driveRow.isSelected
                 z: -1  // Behind content
               }

               // Whole-row click target sits at the back, so the action
               // buttons in front of it capture their own clicks first.
MouseArea {
                 anchors.fill: parent
                 hoverEnabled: true
                 cursorShape: Qt.PointingHandCursor
                 onClicked: {
                   root.driveSelectedIndex = index
                   root.activateDrive(modelData)
                 }
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
                       color: driveRow.isSelected ? root.selectedText
                             : (modelData.mounted ? root.foreground : root.dim)
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
                       else {
                         // The drive auto-opens after mounting, so dismiss
                         // the popup like a row activation would.
                         close()
                         drives.mountDrive(modelData)
                       }
                     }
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