.pragma library

// Progress state. Deliberately not stored in the curriculum repo: pulling new
// lessons must never conflict with having read the old ones, and forking
// somebody's course should inherit their lessons, not their checkmarks.

var VERSION = 1

function empty() {
  return { version: VERSION, completed: {}, last: "" }
}

function load(raw) {
  var doc
  try {
    doc = JSON.parse(String(raw || ""))
  } catch (e) {
    return empty()
  }
  if (!doc || typeof doc !== "object") return empty()

  var completed = {}
  if (doc.completed && typeof doc.completed === "object") {
    for (var k in doc.completed) {
      var v = doc.completed[k]
      if (v) completed[String(k)] = String(v)
    }
  }
  return {
    version: VERSION,
    completed: completed,
    last: doc.last ? String(doc.last) : ""
  }
}

function serialize(state) {
  var s = state || empty()
  return JSON.stringify({
    version: VERSION,
    completed: s.completed || {},
    last: s.last || ""
  }, null, 2)
}

function isDone(state, key) {
  return !!(state && state.completed && state.completed[String(key)])
}

// `stamp` is an ISO date string supplied by the caller — the value is kept so
// a future "what did he do this week" view has something to read.
function setDone(state, key, done, stamp) {
  var next = { version: VERSION, completed: {}, last: state ? state.last || "" : "" }
  var src = state && state.completed ? state.completed : {}
  for (var k in src) next.completed[k] = src[k]
  if (done) next.completed[String(key)] = String(stamp || "")
  else delete next.completed[String(key)]
  return next
}

function setLast(state, key) {
  var next = { version: VERSION, completed: {}, last: String(key || "") }
  var src = state && state.completed ? state.completed : {}
  for (var k in src) next.completed[k] = src[k]
  return next
}

// Two states are equal when they would serialize identically. The progress
// file is watched, so every write comes back as a change notification; without
// this the reload would re-emit and loop.
function same(a, b) {
  return serialize(a) === serialize(b)
}
