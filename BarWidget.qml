import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The bar's job here is small and specific: say where he is without being
// asked, and open the reader in one click. Anything more belongs in the window.
BarWidget {
  id: root
  moduleName: "elementary"

  // The bar hands each widget its own inline shell.json entry as `settings`.
  // The service reads that same entry for itself, so this widget never has to
  // relay configuration — only progress, which the service owns.
  readonly property var svc: (bar && bar.shell && typeof bar.shell.serviceFor === "function")
    ? bar.shell.serviceFor("elementary") : null

  readonly property bool ready: !!svc && svc.ready
  readonly property int done: svc && svc.totals ? Number(svc.totals.done) : 0
  readonly property int total: svc && svc.totals ? Number(svc.totals.total) : 0
  readonly property bool finished: ready && total > 0 && done >= total

  readonly property string label: {
    if (!ready) return "—"
    if (finished) return "done"
    return done + "/" + total
  }

  readonly property string tooltip: {
    if (!svc) return "Elementary"
    if (!ready) return "Elementary — " + (svc.blockedReason || "not set up yet")
    if (finished) return "Elementary — every lesson read"
    var up = svc.nextLesson
    return up
      ? "Elementary — next up: " + up.sectionTitle + " · " + up.title
      : "Elementary — " + done + " of " + total + " read"
  }

  function openReader() {
    if (!bar || !bar.shell) return
    if (typeof bar.shell.toggle === "function") bar.shell.toggle("elementary", "{}")
    else if (typeof bar.shell.summon === "function") bar.shell.summon("elementary", "{}")
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Open book. The label carries the count, so the glyph stays constant and
    // the widget never changes width as he works through a section.
    text: "󰂺  " + root.label
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: root.tooltip
    // Highlighted only when something needs attention — an unconfigured or
    // broken curriculum. Ordinary progress is not an alarm.
    active: !!root.svc && !root.ready
    useActiveColor: true
    activeColor: Color.urgent
    onPressed: root.openReader()
  }
}
