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
  // Entry target queued for power-off after a chained unmount completes.
  property string _pendingEject: ""

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

  // Sanitize untrusted strings: max length, strip control chars
  function sanitize(input, maxLen) {
    if (!input) return ""
    var s = String(input).replace(/[\x00-\x1F\x7F]/g, "")
    return s.length > maxLen ? s.slice(0, maxLen) : s
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
    var text = sanitize(label, 64).trim()
    var m = text.match(/^Local\s+([A-Za-z])$/)
    if (m) return m[1].toUpperCase() + ":"
    if (text.length === 0) return sanitize(name, 32)
    return text
  }

  function parseLsblk(raw) {
    var list = []
    try {
      var json = JSON.parse(raw || "{}")
      var blocks = json.blockdevices || []
      // Build a map of parent disk info by name for looking up transport type
      var parentMap = {}
      for (var i = 0; i < blocks.length; i++) {
        var b = blocks[i]
        if (b && b.name) {
          parentMap[b.name] = { tran: sanitize(b.tran, 32).toLowerCase(), rm: Number(b.rm) === 1 }
        }
      }
      for (var i = 0; i < blocks.length; i++) {
        var b = blocks[i]
        if (!b) continue
        var candidates = (b.children && b.children.length > 0) ? b.children : [b]
        for (var c = 0; c < candidates.length; c++) {
var p = candidates[c]
           if (!p || !p.name) continue
           var type = sanitize(p.type, 32)
           var ejectable = false
           // Only USB/external drives are ejectable: check RM (removable) and TRAN (transport)
           var rm = Number(p.rm) === 1
           var tran = sanitize(p.tran, 32).toLowerCase()
           // For partitions, check parent disk's transport if own tran is null
           if (tran === "" || tran === "null" || tran === "undefined") {
             var parent = parentMap[p.pkname]
             if (parent) tran = parent.tran
           }
           var isUsb = tran === "usb" || tran === "ieee1394" || tran === "thunderbolt"
           if ((type === "disk" || type === "part") && rm && isUsb) {
               ejectable = true
           }
            var entry = {
              name: sanitize(p.name, 32),
              path: sanitize(p.path || ("/dev/" + p.name), 128),
              label: sanitize(p.label, 64),
              mountpoint: sanitize(p.mountpoint, 256),
              fstype: sanitize(p.fstype, 32),
              sizeBytes: Number(p.size) || 0,
              pkname: sanitize(p.pkname, 32),
              ejectable: ejectable
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
    for (var i = 1; i < lines.length && i < 128; i++) {
      var line = lines[i]
      if (!line) continue
      var trimmed = line.replace(/^\s+|\s+$/g, "")
      if (!trimmed) continue
      var match = trimmed.match(/^(\d+)%\s+(\d+)\s+(.+)$/)
      if (!match) continue
      var target = sanitize(match[3], 256)
      out[target] = { percent: parseInt(match[1], 10), used: parseInt(match[2], 10) }
    }
    return out
  }

  function buildDrives(blockList, usageMap) {
    var out = []
    for (var i = 0; i < blockList.length && i < 64; i++) {
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
         busy: busyPath === d.path,
         ejectable: d.ejectable
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
    lsblkTimeout.running = true
  }

  function refreshUsage() {
    if (dfProc.running) return
    dfProc.running = true
    dfTimeout.running = true
  }

  function mountDrive(entry) {
    if (!entry || !entry.path || actionProc.running) return
    busyPath = entry.path
    busy = true
    actionProc.command = ["/usr/bin/udisksctl", "mount", "-b", entry.path]
    actionProc.running = true
    actionTimeout.running = true
  }

function unmountDrive(entry) {
     if (!entry || !entry.path || actionProc.running) return
     busyPath = entry.path
     busy = true
     actionProc.command = ["/usr/bin/udisksctl", "unmount", "-b", entry.path]
     actionProc.running = true
     actionTimeout.running = true
   }

   function ejectDrive(entry) {
     if (!entry || !entry.path || actionProc.running) return
     busyPath = entry.path
     busy = true
     // Power-off targets the whole drive (parent disk), not the partition.
     var target = entry.pkname ? "/dev/" + entry.pkname : entry.path
     if (entry.mounted) {
       // udisksctl power-off refuses while filesystems are mounted:
       // unmount first, then power off from the exit handler.
       _pendingEject = target
       actionProc.command = ["/usr/bin/udisksctl", "unmount", "-b", entry.path]
     } else {
       _pendingEject = null
       actionProc.command = ["/usr/bin/udisksctl", "power-off", "-b", target]
     }
     actionProc.running = true
     actionTimeout.running = true
   }

   function openMountpoint(mountpoint) {
     if (!mountpoint) return
     Util.execArgv(["/usr/bin/xdg-open", mountpoint])
   }

  // TERM→KILL with process group cleanup
  function killProcessGroup(proc) {
    if (!proc.running) return
    try {
      proc.kill("SIGTERM")
      Timer.singleShot(2000, function() {
        if (proc.running) proc.kill("SIGKILL")
      })
    } catch (e) {
      proc.kill("SIGKILL")
    }
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

  // Process timeout timers (at root level)
  Timer {
    id: lsblkTimeout
    interval: 5000
    repeat: false
    running: false
    onTriggered: if (lsblkProc.running) killProcessGroup(lsblkProc)
  }

  Timer {
    id: dfTimeout
    interval: 5000
    repeat: false
    running: false
    onTriggered: if (dfProc.running) killProcessGroup(dfProc)
  }

  Timer {
    id: actionTimeout
    interval: 30000
    repeat: false
    running: false
    onTriggered: if (actionProc.running) killProcessGroup(actionProc)
  }

  Process {
    id: lsblkProc
    command: ["/usr/bin/lsblk", "-J", "-b", "-o", "NAME,PATH,LABEL,MOUNTPOINT,FSTYPE,SIZE,TYPE,PKNAME,RM,TRAN"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root._lastLsblk = text
        root._blocks = root.parseLsblk(text)
        root.usage = root.parseDf(root._lastDf)
        root.drives = root.buildDrives(root._blocks, root.usage)
        root.refreshing = false
        root.loaded = true
        lsblkTimeout.running = false
        root.refreshUsage()
      }
    }
    onExited: function(exitCode) {
      lsblkTimeout.running = false
      root.refreshing = false
      if (exitCode !== 0 && exitCode !== undefined) root.lastError = "lsblk exited " + exitCode
    }
  }

  Process {
    id: dfProc
    command: ["/usr/bin/df", "-B1", "--output=pcent,used,target"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root._lastDf = text
        root.usage = root.parseDf(text)
        if (root._blocks.length > 0) {
          root.drives = root.buildDrives(root._blocks, root.usage)
        }
        dfTimeout.running = false
      }
    }
    onExited: function(exitCode) {
      dfTimeout.running = false
    }
  }

  // Single action process for mount/unmount/eject; command is reassigned each call.
  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
 onExited: function(exitCode) {
       actionTimeout.running = false
       if (exitCode !== 0) {
         var err = String(actionProc.stderr.text || "").trim()
         if (err.length === 0) err = "udisksctl exited " + exitCode
         root.lastError = sanitize(err, 256)
         root._pendingEject = null
       } else {
         root.lastError = ""
         var cmd = actionProc.command || []
         // Chain: a successful unmount that was part of an eject now
         // powers off the drive.
         if (root._pendingEject && cmd.indexOf("unmount") !== -1) {
           var ejectTarget = root._pendingEject
           root._pendingEject = null
           actionProc.command = ["/usr/bin/udisksctl", "power-off", "-b", ejectTarget]
           actionProc.running = true
           return
         }
                 }
                 postActionTimer.restart()
     }
   }

  // udev events trigger a debounced refresh.
  Process {
    id: udevProc
    command: ["/usr/bin/stdbuf", "-oL", "/usr/bin/udevadm", "monitor", "--udev", "--subsystem-match=block"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        var l = sanitize(line, 512)
        if (l.length > 0 && /(add|remove|change|bind|unbind|move)/.test(l)) udevDebounce.restart()
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

  // Supervised restart with exponential backoff (3s, 6s, 12s, 24s, max 60s)
  property int _udevBackoff: 3000
  Timer {
    id: udevRestart
    interval: root._udevBackoff
    repeat: false
    onTriggered: {
      if (!udevProc.running) {
        udevProc.running = true
        root._udevBackoff = Math.min(root._udevBackoff * 2, 60000)
      }
    }
  }
}