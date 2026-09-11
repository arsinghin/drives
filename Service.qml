import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Owns all the system-level work: enumerating drives with lsblk, watching
// udev for live plug/unplug events, sampling usage with df, and dispatching
// udisksctl mount/unmount commands. The Panel just renders what this produces.
Item {
  id: root

  property var settings: ({})

  // The list rendered by the panel. Each entry:
  //   { name, path, label, displayLabel, mountpoint, mounted, sizeBytes,
  //     usedBytes, percent, busy }
  property var drives: []
  property bool refreshing: false
  property bool loaded: false

  // Per-mountpoint usage cache from df, refreshed alongside lsblk.
  property var usage: ({})

  // While a mount/unmount is in flight.
  property bool busy: false
  property string busyPath: ""
  property string lastError: ""

  // user-tunable refresh interval (seconds)
  readonly property int refreshSeconds: {
    var n = parseInt(String(setting("refreshSeconds", 5)), 10)
    if (!isFinite(n)) n = 5
    return Math.max(2, Math.min(300, n))
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // True if the row should be shown: anything with a label, or anything
  // mounted somewhere interesting. Skip pseudo-fs and the rootfs.
  function isUseful(d) {
    if (!d) return false
    var fs = String(d.fstype || "").toLowerCase()
    if (fs === "" || fs === "swap" || fs === "zram" || fs === "rom" || fs === "squashfs") return false
    var mp = d.mountpoint
    if (mp === "/" || mp === "/boot" || mp === "/boot/efi") return false
    var label = String(d.label || "").trim()
    if (label.length > 0) return true
    if (mp) return true
    return false
  }

  // "Local E" -> "E:" — letter-prefix style for old Windows-style labels.
  function displayLabel(label, name) {
    var text = String(label || "").trim()
    var m = text.match(/^Local\s+([A-Za-z])$/)
    if (m) return m[1].toUpperCase() + ":"
    if (text.length === 0) return String(name || "")
    return text
  }

  function parseLsblk(raw) {
    var list = []
    try {
      var json = JSON.parse(raw || "{}")
      var blocks = json.blockdevices || []
      for (var i = 0; i < blocks.length; i++) {
        var b = blocks[i]
        if (!b) continue
        var candidates = (b.children && b.children.length > 0) ? b.children : [b]
        for (var c = 0; c < candidates.length; c++) {
          var p = candidates[c]
          if (!p || !p.name) continue
          var entry = {
            name: String(p.name),
            path: String(p.path || ("/dev/" + p.name)),
            label: String(p.label || ""),
            mountpoint: String(p.mountpoint || ""),
            fstype: String(p.fstype || ""),
            sizeBytes: Number(p.size) || 0
          }
          if (isUseful(entry)) list.push(entry)
        }
      }
    } catch (e) {}
    return list
  }

  // " 47% 50331648 /run/media/onyx/E" -> { target: { percent, used } }
  function parseDf(raw) {
    var out = {}
    var lines = String(raw || "").split("\n")
    for (var i = 1; i < lines.length; i++) {
      var line = lines[i]
      if (!line) continue
      var trimmed = line.replace(/^\s+|\s+$/g, "")
      if (!trimmed) continue
      var match = trimmed.match(/^(\d+)%\s+(\d+)\s+(.+)$/)
      if (!match) continue
      out[match[3]] = { percent: parseInt(match[1], 10), used: parseInt(match[2], 10) }
    }
    return out
  }

  function buildDrives(blockList, usageMap) {
    var out = []
    for (var i = 0; i < blockList.length; i++) {
      var d = blockList[i]
      var u = d.mountpoint ? usageMap[d.mountpoint] : null
      out.push({
        name: d.name,
        path: d.path,
        label: d.label,
        displayLabel: displayLabel(d.label, d.name),
        mountpoint: d.mountpoint,
        mounted: !!d.mountpoint,
        sizeBytes: d.sizeBytes,
        usedBytes: u ? u.used : 0,
        percent: u ? u.percent : 0,
        busy: busyPath === d.path
      })
    }
    return out
  }

  // Cache the parsed block list so a df refresh can rebuild the row data
  // without re-running lsblk.
  property var _blocks: []
  property string _lastLsblk: ""
  property string _lastDf: ""

  function refresh() {
    if (lsblkProc.running || dfProc.running) return
    refreshing = true
    lsblkProc.running = true
  }

  function refreshUsage() {
    if (dfProc.running) return
    dfProc.running = true
  }

  function mountDrive(entry) {
    if (!entry || !entry.path || actionProc.running) return
    busyPath = entry.path
    busy = true
    actionProc.command = ["udisksctl", "mount", "-b", entry.path]
    actionProc.running = true
  }

  function unmountDrive(entry) {
    if (!entry || !entry.path || actionProc.running) return
    busyPath = entry.path
    busy = true
    actionProc.command = ["udisksctl", "unmount", "-b", entry.path]
    actionProc.running = true
  }

  function openMountpoint(mountpoint) {
    if (!mountpoint) return
    Util.execArgv(["xdg-open", mountpoint])
  }

  Component.onCompleted: {
    refresh()
  }

  Timer {
    id: refreshTimer
    interval: root.refreshSeconds * 1000
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: root.refresh()
  }

  // After a mount/unmount action, give udisks2 a moment to settle.
  Timer {
    id: postActionTimer
    interval: 600
    repeat: false
    onTriggered: {
      root.busy = false
      root.busyPath = ""
      root.refresh()
    }
  }

  Process {
    id: lsblkProc
    command: ["lsblk", "-J", "-b", "-o", "NAME,PATH,LABEL,MOUNTPOINT,FSTYPE,SIZE"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root._lastLsblk = text
        root._blocks = root.parseLsblk(text)
        root.usage = root.parseDf(root._lastDf)
        root.drives = root.buildDrives(root._blocks, root.usage)
        root.refreshing = false
        root.loaded = true
        root.refreshUsage()
      }
    }
    onExited: function(exitCode) {
      root.refreshing = false
      if (exitCode !== 0 && exitCode !== undefined) root.lastError = "lsblk exited " + exitCode
    }
  }

  Process {
    id: dfProc
    command: ["df", "-B1", "--output=pcent,used,target"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root._lastDf = text
        root.usage = root.parseDf(text)
        if (root._blocks.length > 0) {
          root.drives = root.buildDrives(root._blocks, root.usage)
        }
      }
    }
  }

  // Single action process for mount/unmount; command is reassigned each call.
  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var err = String(actionProc.stderr.text || "").trim()
        if (err.length === 0) err = "udisksctl exited " + exitCode
        root.lastError = err
      } else {
        root.lastError = ""
      }
      postActionTimer.restart()
    }
  }

  // udev events trigger a debounced refresh.
  Process {
    id: udevProc
    command: ["stdbuf", "-oL", "udevadm", "monitor", "--udev", "--subsystem-match=block"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        if (/(add|remove|change|bind|unbind|move)/.test(String(line))) udevDebounce.restart()
      }
    }
    onExited: udevRestart.restart()
  }

  Timer {
    id: udevDebounce
    interval: 400
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: udevRestart
    interval: 3000
    repeat: false
    onTriggered: if (!udevProc.running) udevProc.running = true
  }
}