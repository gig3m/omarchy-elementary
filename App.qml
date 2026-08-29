import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Curriculum.js" as Curriculum
import "Markdown.js" as Markdown

// The reader. It is meant to sit tiled beside a terminal and be readable from
// across a desk, so: one lesson at a time, a contents list that never scrolls
// out from under you, and controls big enough to hit without aiming.
//
// It reads everything from `service` and writes nothing itself — marking a
// lesson read goes through the service so the bar count moves at the same
// instant the checkmark appears.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false
  property bool closingFromHost: false

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "elementary"

  readonly property color foreground: Color.foreground
  readonly property color background: Color.background
  readonly property color accent: Color.accent
  // Mixed toward the background rather than darkened: on a light theme,
  // darkening an almost-black foreground makes secondary text heavier than
  // body text instead of lighter.
  readonly property color dim: Qt.rgba(
    foreground.r * 0.66 + background.r * 0.34,
    foreground.g * 0.66 + background.g * 0.34,
    foreground.b * 0.66 + background.b * 0.34, 1)
  readonly property color dimmer: Qt.rgba(
    foreground.r * 0.42 + background.r * 0.58,
    foreground.g * 0.42 + background.g * 0.58,
    foreground.b * 0.42 + background.b * 0.58, 1)
  readonly property color rule: Qt.rgba(
    foreground.r * 0.2 + background.r * 0.8,
    foreground.g * 0.2 + background.g * 0.8,
    foreground.b * 0.2 + background.b * 0.8, 1)

  readonly property string fontFamily: Style.font.family

  // Reading size is a real accessibility setting here, not decoration: the
  // person using this is learning to read a screen at the same time as he is
  // learning the machine.
  readonly property int bodySize: {
    var size = service ? String(service.readingSize) : "Large"
    if (size === "Normal") return Math.round(Style.font.body)
    if (size === "Extra large") return Math.round(Style.font.body * 1.5)
    return Math.round(Style.font.body * 1.25)
  }

  // Handed to the inline converter so ==highlights== are painted in the
  // current Omarchy theme rather than hard-coded per lesson. Code and callout
  // surfaces are QML now, so only the highlight pair is needed here.
  readonly property var markdownPalette: ({
    highlightBg: String(root.accent),
    highlightFg: String(root.background)
  })

  readonly property color codeBackground: Qt.rgba(
    foreground.r * 0.10 + background.r * 0.90,
    foreground.g * 0.10 + background.g * 0.90,
    foreground.b * 0.10 + background.b * 0.90, 1)
  readonly property color calloutFill: Qt.rgba(
    accent.r * 0.10 + background.r * 0.90,
    accent.g * 0.10 + background.g * 0.90,
    accent.b * 0.10 + background.b * 0.90, 1)
  readonly property color calloutUrgentFill: Qt.rgba(
    Color.urgent.r * 0.10 + background.r * 0.90,
    Color.urgent.g * 0.10 + background.g * 0.90,
    Color.urgent.b * 0.10 + background.b * 0.90, 1)
  // Machine-specific asides are neutral rather than coloured: they are the
  // concrete half of the lesson, not an alarm and not a tangent.
  readonly property color calloutMachineFill: Qt.rgba(
    foreground.r * 0.07 + background.r * 0.93,
    foreground.g * 0.07 + background.g * 0.93,
    foreground.b * 0.07 + background.b * 0.93, 1)

  readonly property bool ready: !!service && service.ready
  readonly property var sections: service && service.sections ? service.sections : []

  // ------------------------------------------------------------ navigation

  property string currentKey: ""

  readonly property var current: (ready && currentKey)
    ? Curriculum.findByKey(service.course, currentKey) : null
  readonly property var previousLesson: (ready && currentKey)
    ? Curriculum.neighbor(service.course, currentKey, -1) : null
  readonly property var nextLesson: (ready && currentKey)
    ? Curriculum.neighbor(service.course, currentKey, 1) : null
  readonly property bool currentDone: !!service && !!currentKey && service.isDone(currentKey)

  function select(key) {
    if (!key || key === root.currentKey) return
    root.currentKey = String(key)
    if (service) service.rememberLast(root.currentKey)
    bodyScroll.contentY = 0
  }

  // Where to land on open: where he left off, or the first thing unread.
  function restoreposition() {
    if (!ready) return
    if (currentKey && Curriculum.findByKey(service.course, currentKey)) return
    var target = service.resumeLesson
    if (target) {
      root.currentKey = String(target.key)
      bodyScroll.contentY = 0
    }
  }

  function revalidate() {
    if (!ready) { root.currentKey = ""; return }
    if (root.currentKey && !Curriculum.findByKey(service.course, root.currentKey))
      root.currentKey = ""
    restoreposition()
  }

  onReadyChanged: Qt.callLater(root.revalidate)
  Component.onCompleted: Qt.callLater(root.revalidate)

  Connections {
    target: root.service
    function onCourseChanged() { Qt.callLater(root.revalidate) }
  }

  // Marking a lesson read moves you on. Reading the next thing is the whole
  // point of finishing this one, and it saves a second click every time.
  function completeAndAdvance() {
    if (!service || !currentKey) return
    var wasDone = currentDone
    service.markDone(currentKey, !wasDone)
    if (!wasDone && nextLesson) select(nextLesson.key)
  }

  // ------------------------------------------------------------- lifecycle

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(String(payloadJson || "{}")) || ({}) } catch (e) {}
    closingFromHost = false
    opened = true
    if (payload.lesson) select(String(payload.lesson))
    else restoreposition()
  }

  function close() {
    closingFromHost = true
    opened = false
    closingFromHost = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  // --------------------------------------------------------- lesson source

  property var bodyBlocks: []
  property bool bodyMissing: false

  readonly property string bodyPath: (service && current) ? service.lessonPath(current) : ""

  // Pictures are written relative to the lesson file, as they are in every
  // other markdown tool — so `../images/x.png` works the same here, on GitHub,
  // and in Obsidian.
  readonly property string bodyDir: {
    var path = root.bodyPath
    var cut = path.lastIndexOf("/")
    return cut > 0 ? path.substring(0, cut) : ""
  }

  function pictureUrl(src) {
    var raw = String(src || "")
    if (!raw) return ""
    if (/^(https?|qrc|file|data):/.test(raw)) return raw
    if (raw.charAt(0) === "/") return "file://" + raw
    return root.bodyDir ? "file://" + root.bodyDir + "/" + raw : ""
  }

  onBodyPathChanged: {
    if (!root.bodyPath) { root.bodyBlocks = []; root.bodyMissing = false }
  }

  FileView {
    id: lessonFile
    path: root.bodyPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.bodyBlocks = Markdown.blocks(text()); root.bodyMissing = false }
    onFileChanged: reload()
    onLoadFailed: { root.bodyBlocks = []; root.bodyMissing = root.bodyPath !== "" }
  }

  FloatingWindow {
    id: window
    visible: root.opened
    title: root.ready && root.service ? root.service.courseTitle : "Elementary"
    color: root.background
    implicitWidth: Style.space(860)
    implicitHeight: Style.space(680)
    minimumSize: Qt.size(Style.space(520), Style.space(420))

    onVisibleChanged: {
      if (!visible && root.opened && !root.closingFromHost) root.requestClose()
    }

    // Below this the contents list and the lesson cannot both be useful, so the
    // list collapses to a header dropdown-free strip and the lesson takes over.
    readonly property bool narrow: width < Style.space(680)

    FocusScope {
      anchors.fill: parent
      focus: true

      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) { root.requestClose(); event.accepted = true }
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_PageDown) {
          if (root.nextLesson) root.select(root.nextLesson.key)
          event.accepted = true
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_PageUp) {
          if (root.previousLesson) root.select(root.previousLesson.key)
          event.accepted = true
        }
      }

      // ------------------------------------------------------- empty state

      Item {
        anchors.fill: parent
        anchors.margins: Style.space(28)
        visible: !root.ready

        Column {
          anchors.centerIn: parent
          width: Math.min(parent.width, Style.space(420))
          spacing: Style.space(12)

          Text {
            width: parent.width
            text: "Nothing to read yet"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Math.round(Style.font.body * 1.3)
            horizontalAlignment: Text.AlignHCenter
          }
          Text {
            width: parent.width
            text: root.service ? root.service.blockedReason : "Starting up…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: root.bodySize
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }
          Item { width: 1; height: Style.space(4) }
          Button {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.service && root.service.syncing ? "Checking…" : "Try again"
            enabled: !!root.service && !root.service.syncing
            onClicked: root.service.resync()
          }
        }
      }

      // ------------------------------------------------------ contents + body

      Row {
        anchors.fill: parent
        visible: root.ready
        spacing: 0

        // ---- contents

        Rectangle {
          id: sidebar
          width: window.narrow ? 0 : Math.round(Math.min(Style.space(280), window.width * 0.34))
          height: parent.height
          visible: width > 0
          color: "transparent"

          Rectangle {
            anchors.right: parent.right
            width: Style.normalBorderWidth
            height: parent.height
            color: root.rule
          }

          Flickable {
            anchors.fill: parent
            anchors.margins: Style.space(14)
            anchors.rightMargin: Style.space(10)
            contentHeight: contents.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: contents
              width: parent.width
              spacing: Style.space(10)

              Repeater {
                model: root.sections

                Column {
                  required property var modelData
                  width: contents.width
                  spacing: Style.space(2)

                  readonly property var counts: root.service
                    ? root.service.sectionProgress(modelData) : ({ done: 0, total: 0 })

                  Item {
                    width: parent.width
                    height: Style.space(26)

                    PanelSectionHeader {
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      foreground: root.dim
                      fontFamily: root.fontFamily
                      text: modelData.title.toUpperCase()
                    }
                    Text {
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      text: counts.done + "/" + counts.total
                      color: counts.total > 0 && counts.done >= counts.total
                        ? root.accent : root.dimmer
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Repeater {
                    model: modelData.lessons

                    Rectangle {
                      required property var modelData
                      width: contents.width
                      height: Math.max(Style.space(28), title.implicitHeight + Style.space(10))
                      radius: Style.cornerRadius
                      readonly property bool selected: modelData.key === root.currentKey
                      readonly property bool done: !!root.service && root.service.isDone(modelData.key)
                      color: selected ? Style.selectedAccentFill
                        : (hover.hovered ? Style.hoverFill : "transparent")

                      Text {
                        id: mark
                        anchors.left: parent.left
                        anchors.leftMargin: Style.space(6)
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(18)
                        // A read lesson gets a check; everything else gets a
                        // dot, so the column stays aligned and "not yet" never
                        // reads as "locked".
                        text: parent.done ? "✓" : "·"
                        color: parent.done ? root.accent : root.dimmer
                        font.family: root.fontFamily
                        font.pixelSize: root.bodySize
                      }
                      Text {
                        id: title
                        anchors.left: mark.right
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(6)
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.title
                        color: parent.selected ? root.foreground
                          : (parent.done ? root.dim : root.foreground)
                        font.family: root.fontFamily
                        font.pixelSize: Math.round(root.bodySize * 0.92)
                        wrapMode: Text.WordWrap
                      }

                      HoverHandler { id: hover }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.select(modelData.key)
                      }
                    }
                  }
                }
              }
            }
          }
        }

        // ---- lesson

        Item {
          width: parent.width - sidebar.width
          height: parent.height

          Flickable {
            id: bodyScroll
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: footer.top
            anchors.margins: Style.space(22)
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: body
              width: parent.width
              spacing: Style.space(6)

              Text {
                width: parent.width
                visible: !!root.current
                text: root.current ? root.current.sectionTitle.toUpperCase() : ""
                color: root.dimmer
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
              }

              Text {
                width: parent.width
                visible: !!root.current
                text: root.current ? root.current.title : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Math.round(root.bodySize * 1.45)
                wrapMode: Text.WordWrap
              }

              Item { width: 1; height: Style.space(6) }

              // Lessons are plain markdown so the content repo stays editable
              // by hand and readable on the web without this plugin.
              //
              // Prose is handed to Qt, which renders headings, emphasis, lists,
              // tables, quotes and links well. Code and callouts are drawn here
              // instead: injecting them into the markdown as HTML corrupts the
              // rest of the page, and as QML they can follow the theme and be
              // selected on their own.
              Repeater {
                model: root.bodyBlocks

                Column {
                  required property var modelData
                  width: body.width
                  spacing: 0

                  // ---- prose

                  Text {
                    visible: modelData.kind === "prose"
                    width: parent.width
                    text: Markdown.inline(modelData.text, root.markdownPalette)
                    textFormat: Text.MarkdownText
                    color: root.foreground
                    linkColor: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: root.bodySize
                    lineHeight: 1.35
                    wrapMode: Text.WordWrap
                    onLinkActivated: function (link) { Quickshell.execDetached(["xdg-open", link]) }
                  }

                  // ---- a command to type

                  Rectangle {
                    visible: modelData.kind === "code"
                    width: parent.width
                    height: visible ? codeText.implicitHeight + Style.space(20) : 0
                    radius: Style.cornerRadius
                    color: root.codeBackground

                    // Selectable, because the point of a command on the page is
                    // that it ends up in the terminal next to it.
                    TextEdit {
                      id: codeText
                      anchors.fill: parent
                      anchors.margins: Style.space(10)
                      text: modelData.kind === "code" ? modelData.text : ""
                      readOnly: true
                      selectByMouse: true
                      color: root.foreground
                      selectionColor: Style.selectionFill
                      font.family: root.fontFamily
                      font.pixelSize: root.bodySize
                      wrapMode: TextEdit.NoWrap
                    }
                  }

                  // ---- a picture
                  //
                  // Worth the trouble for a reader this young: a breadboard is
                  // a photograph, not a paragraph. Qt's markdown drops images
                  // entirely, so this is a real Image drawn from the block.

                  Column {
                    visible: modelData.kind === "image"
                    width: parent.width
                    spacing: Style.space(4)

                    Image {
                      id: picture
                      source: modelData.kind === "image" ? root.pictureUrl(modelData.src) : ""
                      asynchronous: true
                      fillMode: Image.PreserveAspectFit
                      // Never blown up past its own resolution: an upscaled
                      // diagram is harder to read than a small sharp one.
                      width: Math.min(parent.width, implicitWidth)
                      height: implicitWidth > 0
                        ? implicitHeight * (width / implicitWidth) : 0
                    }

                    Text {
                      visible: picture.status === Image.Ready && modelData.alt !== ""
                      width: parent.width
                      text: modelData.kind === "image" ? modelData.alt : ""
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Math.round(root.bodySize * 0.85)
                      wrapMode: Text.WordWrap
                    }

                    Text {
                      visible: picture.status === Image.Error
                      width: parent.width
                      text: "Missing picture: " + (modelData.kind === "image" ? modelData.src : "")
                      color: Color.urgent
                      font.family: root.fontFamily
                      font.pixelSize: Math.round(root.bodySize * 0.85)
                      wrapMode: Text.WordWrap
                    }
                  }

                  // ---- an aside

                  Rectangle {
                    visible: modelData.kind === "callout"
                    width: parent.width
                    height: visible ? calloutBody.implicitHeight + calloutLabel.implicitHeight
                      + Style.space(26) : 0
                    radius: Style.cornerRadius
                    color: modelData.tone === "urgent" ? root.calloutUrgentFill
                      : (modelData.tone === "machine" ? root.calloutMachineFill : root.calloutFill)

                    Rectangle {
                      id: calloutBar
                      width: Style.space(3)
                      height: parent.height
                      radius: parent.radius
                      color: modelData.tone === "urgent" ? Color.urgent
                        : (modelData.tone === "machine" ? root.dim : root.accent)
                    }

                    Text {
                      id: calloutLabel
                      anchors.top: parent.top
                      anchors.topMargin: Style.space(10)
                      anchors.left: calloutBar.right
                      anchors.leftMargin: Style.space(12)
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(12)
                      text: modelData.kind === "callout" ? modelData.label : ""
                      color: modelData.tone === "urgent" ? Color.urgent
                        : (modelData.tone === "machine" ? root.dim : root.accent)
                      font.family: root.fontFamily
                      font.pixelSize: Math.round(root.bodySize * 0.9)
                      font.bold: true
                      elide: Text.ElideRight
                    }

                    Text {
                      id: calloutBody
                      anchors.top: calloutLabel.bottom
                      anchors.topMargin: Style.space(4)
                      anchors.left: calloutBar.right
                      anchors.leftMargin: Style.space(12)
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(12)
                      text: modelData.kind === "callout"
                        ? Markdown.inline(modelData.body, root.markdownPalette) : ""
                      textFormat: Text.MarkdownText
                      color: root.foreground
                      linkColor: root.accent
                      font.family: root.fontFamily
                      font.pixelSize: root.bodySize
                      lineHeight: 1.35
                      wrapMode: Text.WordWrap
                      onLinkActivated: function (link) { Quickshell.execDetached(["xdg-open", link]) }
                    }
                  }
                }
              }

              Text {
                width: parent.width
                visible: root.bodyMissing
                text: "This lesson's file is missing:\n" + root.bodyPath
                color: Color.urgent
                font.family: root.fontFamily
                font.pixelSize: root.bodySize
                wrapMode: Text.WordWrap
              }
            }
          }

          // ---- footer

          Item {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Style.space(58)

            Rectangle {
              anchors.top: parent.top
              width: parent.width
              height: Style.normalBorderWidth
              color: root.rule
            }

            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(22)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Button {
                text: "‹ Back"
                enabled: !!root.previousLesson
                onClicked: root.select(root.previousLesson.key)
              }
              Button {
                text: "Next ›"
                enabled: !!root.nextLesson
                onClicked: root.select(root.nextLesson.key)
              }
            }

            Button {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(22)
              anchors.verticalCenter: parent.verticalCenter
              enabled: !!root.current
              text: root.currentDone ? "✓ Read" : "Mark as read"
              onClicked: root.completeAndAdvance()
            }
          }
        }
      }
    }
  }
}
