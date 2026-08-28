import QtQuick
import Quickshell
import Quickshell.Io
import "Curriculum.js" as Curriculum
import "Progress.js" as Progress

// Elementary's service half: it owns the curriculum on disk and the record of
// what has been read. Both the bar widget and the reader window are renderers
// over this object, so "how far along is he" has exactly one answer no matter
// which one you ask.
//
// The service exists rather than letting the window own state because the bar
// has to show progress while the window is closed, and because a sync should
// not restart every time the window is summoned.
Item {
  id: root

  property var shell: null
  property var manifest: null

  // The registry stamps __sourceDir onto every manifest it scans, but hands the
  // manifest over only after createObject returns — so during construction the
  // resolved URL of this file is the value actually available.
  readonly property string pluginPath: {
    var stamped = root.manifest && root.manifest.__sourceDir ? String(root.manifest.__sourceDir) : ""
    if (stamped) return stamped.replace(/\/+$/, "")
    return String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/+$/, "")
  }

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME")
    || (Quickshell.env("HOME") + "/.local/state")) + "/elementary"

  // ------------------------------------------------------------- settings
  //
  // A service is never handed `settings` — only bar widgets are. Both halves
  // read the same inline entry out of shell.json instead, searching bar.layout
  // before plugins[] because that is the order the shell's own write path uses.
  readonly property var settingsEntry: {
    var config = root.shell && root.shell.shellConfig ? root.shell.shellConfig : null
    if (!config) return null
    var sections = ["left", "center", "right"]
    var layout = config.bar && config.bar.layout ? config.bar.layout : null
    if (layout) {
      for (var s = 0; s < sections.length; s++) {
        var arr = layout[sections[s]]
        if (!Array.isArray(arr)) continue
        for (var i = 0; i < arr.length; i++)
          if (arr[i] && String(arr[i].id) === "elementary") return arr[i]
      }
    }
    if (Array.isArray(config.plugins)) {
      for (var j = 0; j < config.plugins.length; j++)
        if (config.plugins[j] && String(config.plugins[j].id) === "elementary")
          return config.plugins[j]
    }
    return null
  }

  function setting(key, fallback) {
    var e = root.settingsEntry
    return e && (key in e) && e[key] !== "" && e[key] !== null ? e[key] : fallback
  }

  // Named `curriculum`, not `source`: a bar layout entry carrying a `source`
  // key is claimed by the bar as a custom QML module (BarModel.customModuleType),
  // which discards the registered plugin widget and tries to load the value as
  // a QML file. `exec` and `type` are reserved the same way.
  //
  // `source` is still read as a fallback so a config written before the rename
  // keeps showing lessons while the migration below repairs it.
  readonly property string source: String(setting("curriculum", "") || setting("source", ""))
  readonly property string branch: String(setting("branch", "main"))
  readonly property bool autoSync: String(setting("autoSync", "On")) !== "Off"
  readonly property int syncIntervalMin: Math.max(5, Number(setting("syncIntervalMin", 60)) || 60)
  readonly property string readingSize: String(setting("readingSize", "Large"))

  // ----------------------------------------------------------- migration

  // Configs written before the setting was renamed carry `source`, which the
  // bar claims for custom QML modules — the widget is then silently dropped
  // and no amount of updating the plugin brings it back, because the stale key
  // lives in shell.json rather than in the plugin.
  //
  // `omarchy bar set` cannot fix it either: it merges into the existing entry,
  // so the poisoned key survives. updateEntryInline replaces the entry
  // outright, which is what actually removes it.
  property bool migrationChecked: false

  readonly property var settingKeys: ["curriculum", "branch", "autoSync",
    "syncIntervalMin", "readingSize"]

  function migrateLegacySettings() {
    if (root.migrationChecked) return
    var entry = root.settingsEntry
    // The config may not have been read yet; try again when it changes.
    if (!entry) return
    root.migrationChecked = true

    var reserved = ["source", "exec", "type"]
    var poisoned = false
    for (var r = 0; r < reserved.length; r++)
      if (entry[reserved[r]] !== undefined) poisoned = true
    if (!poisoned) return

    if (!root.shell || typeof root.shell.updateEntryInline !== "function") {
      console.warn("elementary: shell.json carries a reserved `source` key, which hides"
        + " the bar widget, and this shell offers no way to rewrite the entry."
        + " Remove `source` from the elementary entry by hand.")
      return
    }

    var next = ({})
    for (var i = 0; i < root.settingKeys.length; i++) {
      var key = root.settingKeys[i]
      if (entry[key] !== undefined) next[key] = entry[key]
    }
    // Carry the old value across rather than dropping the user's curriculum.
    if (!next.curriculum && entry.source) next.curriculum = String(entry.source)

    root.shell.updateEntryInline("elementary", next)
    console.log("elementary: removed a reserved `source` key from shell.json"
      + " and moved its value to `curriculum`; the bar widget can render now.")
  }

  onSettingsEntryChanged: Qt.callLater(root.migrateLegacySettings)

  // ------------------------------------------------------------- curriculum

  property string curriculumPath: ""
  property string syncMode: ""          // local | clone | pull | stale | error | none
  property string syncMessage: ""
  property bool syncOk: false
  property bool syncing: false

  property var course: ({ ok: false, title: "", sections: [], error: "" })
  readonly property bool ready: course && course.ok === true
  readonly property string courseTitle: course && course.title ? course.title : "Elementary"
  readonly property var sections: course && course.sections ? course.sections : []
  readonly property var lessons: Curriculum.flatten(root.course)

  // The one sentence the window shows when it has nothing to render. Ordered
  // most-actionable first: an unset source is a different problem from a repo
  // that downloaded but has no course.json in it.
  readonly property string blockedReason: {
    if (root.ready) return ""
    if (!root.source) return "No curriculum yet. Open the bar widget's settings and point “Curriculum source” at a git URL or a folder on this computer."
    if (!root.syncOk) return root.syncMessage || "Could not load the curriculum."
    if (root.course && root.course.error) return root.course.error
    return "Loading…"
  }

  function resync() {
    if (syncProc.running) return
    root.syncing = true
    syncProc.command = [root.pluginPath + "/scripts/curriculum-sync.sh", root.source, root.branch]
    syncProc.running = true
  }

  function applySync(raw) {
    root.syncing = false
    var d = null
    try { d = JSON.parse(String(raw || "")) } catch (e) { d = null }
    if (!d) {
      root.syncOk = false
      root.syncMode = "error"
      root.syncMessage = "The curriculum sync did not answer."
      return
    }
    root.syncOk = d.ok === true
    root.syncMode = String(d.mode || "")
    root.syncMessage = String(d.message || "")
    var path = String(d.path || "")
    if (path && path !== root.curriculumPath) root.curriculumPath = path
    else if (path) courseFile.reload()
    if (!path) root.course = ({ ok: false, title: "", sections: [], error: "" })
  }

  onSourceChanged: Qt.callLater(root.resync)
  onBranchChanged: Qt.callLater(root.resync)

  Process {
    id: syncProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applySync(text) }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function (code) {
      if (code !== 0 && root.syncing) root.applySync("")
    }
  }

  Timer {
    interval: root.syncIntervalMin * 60 * 1000
    running: root.autoSync && root.source !== ""
    repeat: true
    triggeredOnStart: true
    onTriggered: root.resync()
  }

  // Even with auto-sync off the curriculum still has to be located once.
  Component.onCompleted: {
    Qt.callLater(root.migrateLegacySettings)
    Qt.callLater(root.resync)
  }

  FileView {
    id: courseFile
    path: root.curriculumPath ? root.curriculumPath + "/course.json" : ""
    watchChanges: true
    printErrors: false
    onLoaded: root.course = Curriculum.parse(text())
    onFileChanged: reload()
    onLoadFailed: root.course = ({
      ok: false, title: "", sections: [],
      error: root.curriculumPath ? "No course.json in " + root.curriculumPath : ""
    })
  }

  // Lesson bodies are read on demand by the window rather than held here: a
  // course can be large, and only one lesson is ever on screen.
  function lessonPath(lesson) {
    if (!lesson || !root.curriculumPath) return ""
    return root.curriculumPath + "/" + String(lesson.file).replace(/^\/+/, "")
  }

  // ------------------------------------------------------------- progress

  property var progress: Progress.empty()
  property bool progressLoaded: false
  property string progressPayload: ""
  property bool progressQueued: false

  readonly property var completed: root.progress && root.progress.completed
    ? root.progress.completed : ({})
  readonly property string lastKey: root.progress ? String(root.progress.last || "") : ""
  readonly property var totals: Curriculum.totals(root.course, root.completed)
  readonly property var nextLesson: Curriculum.nextUp(root.course, root.completed)
  readonly property var resumeLesson: Curriculum.resume(root.course, root.completed, root.lastKey)

  function isDone(key) { return Progress.isDone(root.progress, key) }

  function sectionProgress(section) {
    return Curriculum.sectionProgress(section, root.completed)
  }

  function markDone(key, done) {
    if (!key) return
    var stamp = new Date().toISOString()
    var next = Progress.setDone(root.progress, key, done === true, stamp)
    if (Progress.same(next, root.progress)) return
    root.progress = next
    saveProgress()
  }

  function toggleDone(key) { markDone(key, !isDone(key)) }

  function rememberLast(key) {
    if (!key) return
    var next = Progress.setLast(root.progress, key)
    if (Progress.same(next, root.progress)) return
    root.progress = next
    saveProgress()
  }

  function saveProgress() {
    if (!progressLoaded) return
    if (progressWriter.running) { root.progressQueued = true; return }
    root.progressQueued = false
    root.progressPayload = Progress.serialize(root.progress)
    progressWriter.command = [root.pluginPath + "/scripts/state-store.sh", "progress.json"]
    progressWriter.running = true
  }

  function applyProgress(raw) {
    var loaded = Progress.load(raw)
    root.progressLoaded = true
    // The file is watched so an edit from outside is honoured, but our own
    // writes come back through the same watch. Reassigning an identical state
    // would re-trigger every binding that reads it.
    if (Progress.same(loaded, root.progress)) return
    root.progress = loaded
  }

  FileView {
    id: progressFile
    path: root.stateDir + "/progress.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyProgress(text())
    onFileChanged: reload()
    // Nothing read yet is the ordinary first-run state, not an error.
    onLoadFailed: root.applyProgress("")
  }

  Process {
    id: progressWriter
    stdinEnabled: true
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onStarted: {
      write(root.progressPayload + "\n")
      root.progressPayload = ""
    }
    onExited: {
      root.progressPayload = ""
      if (root.progressQueued) root.saveProgress()
    }
  }

  // Lets `omarchy-shell elementary resync` kick a pull from a lesson-authoring
  // script without opening the window.
  IpcHandler {
    target: "elementary"
    function resync(): void { root.resync() }
    function open(): void {
      if (!root.shell) return
      if (typeof root.shell.toggle === "function") root.shell.toggle("elementary", "{}")
      else if (typeof root.shell.summon === "function") root.shell.summon("elementary", "{}")
    }
    function status(): string {
      return JSON.stringify({
        ready: root.ready,
        path: root.curriculumPath,
        mode: root.syncMode,
        message: root.syncMessage,
        done: root.totals.done,
        total: root.totals.total
      })
    }
  }
}
