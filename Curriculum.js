.pragma library

// Pure model for the curriculum. Nothing here touches the filesystem or QML —
// Service.qml does the I/O and hands the raw text in, so every rule about what
// a course *is* stays testable without a shell running.

var SECTION_KEYS = ["id", "title", "summary"]

function _str(v, fallback) {
  return v === undefined || v === null ? (fallback || "") : String(v)
}

// A lesson's identity is section id + lesson id, never its filename. Renaming
// `01-mouse.md` to `01-the-mouse.md` is an editorial act and must not throw
// away the fact that he already read it.
function keyOf(sectionId, lessonId) {
  return String(sectionId) + "/" + String(lessonId)
}

// Returns { ok, title, sections, error }. A malformed course.json is reported,
// never thrown: the window has to render *something* when the content repo is
// mid-edit, and "your course.json is broken" is more use than a blank pane.
function parse(raw) {
  var doc
  try {
    doc = JSON.parse(String(raw || ""))
  } catch (e) {
    return { ok: false, title: "", sections: [], error: "course.json is not valid JSON: " + e }
  }
  if (!doc || typeof doc !== "object")
    return { ok: false, title: "", sections: [], error: "course.json is empty" }
  if (!Array.isArray(doc.sections))
    return { ok: false, title: "", sections: [], error: "course.json has no `sections` array" }

  var sections = []
  var seenSection = {}
  for (var i = 0; i < doc.sections.length; i++) {
    var s = doc.sections[i]
    if (!s || !s.id) continue
    var sid = _str(s.id)
    // Duplicate ids would give two lessons the same progress key and let one
    // silently mark the other done.
    if (seenSection[sid]) continue
    seenSection[sid] = true

    var lessons = []
    var seenLesson = {}
    var rawLessons = Array.isArray(s.lessons) ? s.lessons : []
    for (var j = 0; j < rawLessons.length; j++) {
      var l = rawLessons[j]
      if (!l || !l.id || !l.file) continue
      var lid = _str(l.id)
      if (seenLesson[lid]) continue
      seenLesson[lid] = true
      lessons.push({
        id: lid,
        title: _str(l.title, lid),
        file: _str(l.file),
        key: keyOf(sid, lid),
        sectionId: sid,
        sectionTitle: _str(s.title, sid)
      })
    }

    sections.push({
      id: sid,
      title: _str(s.title, sid),
      summary: _str(s.summary),
      lessons: lessons
    })
  }

  if (sections.length === 0)
    return { ok: false, title: _str(doc.title), sections: [], error: "course.json lists no usable sections" }

  return { ok: true, title: _str(doc.title, "Curriculum"), sections: sections, error: "" }
}

// Reading order, flattened. The sidebar renders sections; everything else
// (next, previous, overall progress) wants one ordered list.
function flatten(course) {
  var out = []
  if (!course || !course.sections) return out
  for (var i = 0; i < course.sections.length; i++)
    for (var j = 0; j < course.sections[i].lessons.length; j++)
      out.push(course.sections[i].lessons[j])
  return out
}

function findByKey(course, key) {
  var all = flatten(course)
  for (var i = 0; i < all.length; i++)
    if (all[i].key === String(key)) return all[i]
  return null
}

function indexOfKey(course, key) {
  var all = flatten(course)
  for (var i = 0; i < all.length; i++)
    if (all[i].key === String(key)) return i
  return -1
}

function neighbor(course, key, step) {
  var all = flatten(course)
  var at = indexOfKey(course, key)
  if (at === -1) return null
  var next = at + step
  return next >= 0 && next < all.length ? all[next] : null
}

function sectionProgress(section, completed) {
  var done = 0
  var lessons = section && section.lessons ? section.lessons : []
  for (var i = 0; i < lessons.length; i++)
    if (completed && completed[lessons[i].key]) done++
  return { done: done, total: lessons.length }
}

function totals(course, completed) {
  var all = flatten(course)
  var done = 0
  for (var i = 0; i < all.length; i++)
    if (completed && completed[all[i].key]) done++
  return { done: done, total: all.length }
}

// The first unread lesson in reading order. Progress is soft — nothing is
// locked — so this is a suggestion the window highlights, not a gate.
function nextUp(course, completed) {
  var all = flatten(course)
  for (var i = 0; i < all.length; i++)
    if (!completed || !completed[all[i].key]) return all[i]
  return all.length ? all[all.length - 1] : null
}

// Which lesson the window should show on open: where he left off if that
// lesson still exists, otherwise the first thing he has not read.
function resume(course, completed, lastKey) {
  var found = lastKey ? findByKey(course, lastKey) : null
  return found || nextUp(course, completed)
}
