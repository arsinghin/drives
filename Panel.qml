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
   property bool searchMode: false          // false = key mode, true = search mode
   property int infoDriveIndex: -1          // index of drive whose info to show in bottom area (-1 = none)
   property var pinnedPaths: []             // drive paths pinned to the top of the list
  property string _postMountAction: ""      // "terminal" or "filemanager"
  property string _postMountPath: ""        // device path to watch for
  Timer {
    id: mountPollTimer
    interval: 500
    repeat: true
    running: false
    onTriggered: {
      for (var i = 0; i < drives.drives.length; i++) {
        if (drives.drives[i].path === root._postMountPath &&
            drives.drives[i].mounted && drives.drives[i].mountpoint) {
          mountPollTimer.running = false
          if (root._postMountAction === "terminal") {
            Util.execArgv(["/usr/bin/foot", "--working-directory=" + drives.drives[i].mountpoint])
          } else if (root._postMountAction === "filemanager") {
            drives.openMountpoint(drives.drives[i].mountpoint)
          }
          root._postMountAction = ""
          root._postMountPath = ""
          break
        }
      }
    }
  }

  Component.onCompleted: {
    updateFilteredDrives(true)
  }

// resetToTop: true when the result set should highlight its top row
   // (popup open, search text changed); false for background drive-list
   // refreshes so a selection the user is browsing is preserved.
   function updateFilteredDrives(resetToTop) {
     var list
     // When not in search mode, show all drives
     if (!root.searchMode) {
       list = drives.drives
     } else {
       // In search mode, apply the filter
       if (!driveSearchText) {
         list = drives.drives
       } else {
         var term = driveSearchText.toLowerCase()
         list = drives.drives.filter(function(drive) {
           // Search in label, displayLabel, name, and mountpoint
           return (drive.label && drive.label.toLowerCase().includes(term)) ||
                  (drive.displayLabel && drive.displayLabel.toLowerCase().includes(term)) ||
                  (drive.name && drive.name.toLowerCase().includes(term)) ||
                  (drive.mountpoint && drive.mountpoint.toLowerCase().includes(term))
         })
       }
     }
     // Pinned drives float to the top; everything else keeps its order.
     if (pinnedPaths.length > 0) {
       var pinned = []
       var rest = []
       for (var i = 0; i < list.length; i++) {
         if (pinnedPaths.indexOf(list[i].path) !== -1) pinned.push(list[i])
         else rest.push(list[i])
       }
       list = pinned.concat(rest)
     }
     driveFilteredDrives = list
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
     root.infoDriveIndex = root.driveSelectedIndex   // keep info area in sync
   }

function navDown() {
     if (driveFilteredDrives.length === 0) return
     driveSelectedIndex = Math.min(driveFilteredDrives.length - 1,
                                   (driveSelectedIndex < 0 ? -1 : driveSelectedIndex) + 1)
     scrollToSelected()
     root.infoDriveIndex = root.driveSelectedIndex   // keep info area in sync
   }

function activateSelected() {
     if (driveSelectedIndex >= 0 && driveSelectedIndex < driveFilteredDrives.length) {
       activateDrive(driveFilteredDrives[driveSelectedIndex])
     }
     root.infoDriveIndex = root.driveSelectedIndex   // keep info area in sync
   }

   // Currently selected drive (or null).
   function selectedDrive() {
     if (driveSelectedIndex < 0 || driveSelectedIndex >= driveFilteredDrives.length) return null
     return driveFilteredDrives[driveSelectedIndex]
   }

   function keyMount() {
     var d = selectedDrive()
     if (d && !d.mounted) drives.mountDrive(d)
     root.infoDriveIndex = root.driveSelectedIndex
   }

   function keyUnmount() {
     var d = selectedDrive()
     if (d && d.mounted) drives.unmountDrive(d)
     root.infoDriveIndex = root.driveSelectedIndex
   }

   function keyEject() {
     var d = selectedDrive()
     if (d && d.mounted) drives.ejectDrive(d)
     root.infoDriveIndex = root.driveSelectedIndex
   }

   function keyTerminal() {
           var d = selectedDrive()
           if (!d) return
           if (d.mounted && d.mountpoint) {
             close()
             Util.execArgv(["/usr/bin/foot", "--working-directory=" + d.mountpoint])
           } else if (!d.mounted) {
             close()
             drives.mountDrive(d)
             root._postMountAction = "terminal"
             root._postMountPath = d.path
             root.mountPollTimer.running = true
           }
         }

   function keyPin() {
     var d = selectedDrive()
     if (!d) return
     if (pinnedPaths.indexOf(d.path) === -1) {
       pinnedPaths = pinnedPaths.concat([d.path])
     } else {
       pinnedPaths = pinnedPaths.filter(function(p) { return p !== d.path })
     }
     updateFilteredDrives(false)
   }

  // Keep the selected row visible in the flickable. Uses the Repeater's
  // itemAt() so we don't need ids from inside the delegate scope.
   function scrollToSelected() {
     if (driveSelectedIndex < 0) return
     Qt.callLater(function() {
       var item = driveRepeater.itemAt(driveSelectedIndex)
       if (!item || listFlick.contentHeight <= listFlick.height) return
       var top = item.y
       var bottom = item.y + item.height
       if (top < listFlick.contentY) {
         listFlick.contentY = top
       } else if (bottom > listFlick.contentY + listFlick.height) {
         listFlick.contentY = bottom - listFlick.height
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
    else {
      drives.mountDrive(d)
      root._postMountAction = "filemanager"
      root._postMountPath = d.path
      root.mountPollTimer.running = true
    }
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
    // Start in key mode (not search mode)
    root.searchMode = false
    keyCatcher.forceActiveFocus()    // initial focus on key container
}

Timer {
    id: searchFocusTimer
    interval: 60
    repeat: false
    onTriggered: {
        if (root.searchMode) {
            searchField.forceActiveFocus()
        }
    }
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

   // Re-run the filter whenever the service produces a new drive list, so
   // the popup stays in sync after mounts/unmounts/plug events. Selection
   // is preserved (resetToTop false) so browsing isn't disturbed.
   Connections {
     target: drives
     function onDrivesChanged() {
       root.updateFilteredDrives(false)
     }
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
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        // Short-circuit the catcher while the search field has focus so
        // typed letters reach the field instead of triggering actions.
        blocked: searchField.activeFocus

        onCloseRequested: root.close()

        Keys.onUpPressed: root.navUp()
        Keys.onDownPressed: root.navDown()
        Keys.onEnterPressed: root.activateSelected()
        Keys.onReturnPressed: root.activateSelected()
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Slash) {
                if (!root.searchMode) {
                    root.searchMode = true
                    root.driveSearchText = ""   // clear search when activating
                    searchField.forceActiveFocus()
                }
                event.accepted = true
                return
            }
            // Shortcut actions, matching the footer: t/p/m/u/e.
            // They act on the selected drive; m/u/e leave the popup open.
            var k = event.text
            if (k === "m") { root.keyMount(); event.accepted = true }
            else if (k === "u") { root.keyUnmount(); event.accepted = true }
            else if (k === "e") { root.keyEject(); event.accepted = true }
            else if (k === "t") { root.keyTerminal(); event.accepted = true }
            else if (k === "p") { root.keyPin(); event.accepted = true }
        }
        Keys.onEscapePressed: {
            if (root.searchMode) {
                root.searchMode = false     // exit to key mode
                keyCatcher.forceActiveFocus() // return focus to key container
            } else {
                root.close()                // close plugin from key mode
            }
        }

       ColumnLayout {
         id: column
         anchors.fill: parent
         spacing: Style.space(10)

          PanelHero {
            id: hero
            Layout.fillWidth: true
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
             Layout.fillWidth: true
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
              Layout.fillWidth: true
             placeholderText: "Search drives…"
             text: root.driveSearchText
             color: root.foreground
             font.family: root.fontFamily
             font.pixelSize: Style.font.body
             leftPadding: Style.space(8)
             rightPadding: Style.space(8)
onTextChanged: {
        // Only update filter when in search mode
        if (root.searchMode) {
          root.driveSearchText = text
          root.updateFilteredDrives(true)
        }
      }
             Keys.onUpPressed: root.navUp()
             Keys.onDownPressed: root.navDown()
             Keys.onReturnPressed: root.activateSelected()
             Keys.onEnterPressed: root.activateSelected()
             Keys.onEscapePressed: {
        if (root.searchMode) {
            root.searchMode = false     // exit to key mode
            keyCatcher.forceActiveFocus() // return focus to key container
        } else {
            root.close()                // close plugin from key mode
        }
      }
            }

            // Drive list: the only scrolling region. The header (hero, error,
            // search box) and the footer (drive info, shortcuts) stay fixed.
            Flickable {
              id: listFlick
              Layout.fillWidth: true
              Layout.fillHeight: true
              Layout.preferredHeight: Math.min(listColumn.implicitHeight, Style.space(400))
              contentWidth: width
              contentHeight: listColumn.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              flickableDirection: Flickable.VerticalFlick
              interactive: contentHeight > height
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              Column {
                id: listColumn
                width: listFlick.width
                spacing: Style.space(10)

            Repeater {
              id: driveRepeater
             model: root.driveFilteredDrives

delegate: Item {
                id: driveRow
                required property var modelData
                required property int index

                width: parent.width
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
                    root.infoDriveIndex = index   // update info area to show this drive
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

                     // Pin marker for drives pinned via the 'p' shortcut.
                     Text {
                       textFormat: Text.PlainText
                       visible: root.pinnedPaths.indexOf(modelData.path) !== -1
                       text: "\uf08d"  // fa-thumbtack
                       color: root.foreground
                       font.family: root.fontFamily
                       font.pixelSize: Style.font.caption
                     }

Text {
                        textFormat: Text.PlainText
                        text: modelData.mounted ? modelData.mountpoint : modelData.path
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
                                // the row's open/mount handler. The column hugs the single
                                // button, so it lands flush at the row's right edge with the
                                // same margin as the row padding.
                                Column {
                                   Layout.alignment: Qt.AlignVCenter
                                   Layout.preferredWidth: Style.space(28)
                                   spacing: Style.space(8)

                                    PanelActionButton {
                                      width: Style.space(28)
                                      height: Style.space(28)
                                      // Determine icon, tooltip, and action.
                                      // Unmounted: + / Mount
                                      // Mounted + ejectable: ⏏ / Eject (power-off)
                                      // Mounted + not ejectable: × / Unmount
                                      property var actionType:
                                          modelData.mounted ?
                                              (modelData.ejectable ? "eject" : "unmount") :
                                              "mount"
                                      iconText:
                                          actionType === "mount" ? "\uf067" :        // fa-plus
                                          (actionType === "eject" ? "\uf052" : "\uf00d")  // fa-eject / fa-close (×)
                                      tooltipText:
                                                                actionType === "mount" ? "Mount " + modelData.displayLabel :
                                                                (actionType === "eject" ? "Eject " + modelData.displayLabel + " (" + modelData.path + ")" :
                                                                                         "Unmount " + modelData.displayLabel + " (" + modelData.path + ")")
                                      foreground: modelData.mounted ?
                                          (modelData.ejectable ? Color.urgent : root.foreground) :
                                          root.foreground
                                      hoverColor: foreground
                                      fontFamily: root.fontFamily
                                      fontSize: Style.font.body
                                      bordered: true
                                      enabled: !drives.busy || drives.busyPath !== modelData.path
                                      onClicked: {
                                          if (actionType === "mount") {
                                              close()
                                              drives.mountDrive(modelData)
                                          } else if (actionType === "eject") {
                                              close()
                                              drives.ejectDrive(modelData)
                                          } else { // unmount
                                              close()
                                              drives.unmountDrive(modelData)
                                          }
                                      }
                                    }
                                 }
}
              }
            }
              }
            }

            // Drive info area (shows the selected drive's filesystem)
            Text {
                id: infoText
                textFormat: Text.PlainText
                visible: false
                Layout.fillWidth: true
               leftPadding: Style.space(12)
               rightPadding: Style.space(12)
                 // Build info string from selected drive
                 text: {
                    var drive = root.driveFilteredDrives[root.infoDriveIndex]
                    if (!drive) return ""

                    var parts = []
                    if (drive.label && drive.label !== drive.name) parts.push("Label: " + drive.label)
                    if (drive.fstype) parts.push("FS: " + drive.fstype)
                    if (drive.sizeBytes > 0) parts.push("Size: " + root.formatBytes(drive.sizeBytes))
                    if (drive.mounted && drive.mountpoint) parts.push("Mounted: " + drive.mountpoint)
                    if (drive.path) parts.push("Device: " + drive.path)

                    return parts.join("   ")
                }
               color: root.dim
               font.family: root.fontFamily
               font.pixelSize: Style.font.caption
               wrapMode: Text.WordWrap
           }
           
             Text {
               textFormat: Text.PlainText
               visible: drives.loaded && drives.drives.length === 0
               Layout.fillWidth: true
               text: "No labeled or mounted drives are visible right now."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            // Keyboard shortcuts footer. Shown once at the bottom of the
            // popup — only when drives are actually listed. Wraps to the
            // next line when it doesn't fit.
            Text {
              textFormat: Text.PlainText
              visible: drives.drives.length > 0
              Layout.fillWidth: true
              text: "/: Type   t: Open in terminal   p: Pin/unpin   m: Mount   u: Unmount   e: Eject"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
          }
      }
  }
}
