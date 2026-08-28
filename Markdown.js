.pragma library

// Lesson markdown -> a list of blocks the reader can render.
//
// Qt's Text.MarkdownText is good at prose: headings, bold, italic,
// strikethrough, lists, tables, links, block quotes and inline code all render
// correctly and are left to it. It has no notion of three things a curriculum
// like this one needs:
//
//   ==highlight==   the thing on the page he is meant to notice
//   > [!note]       an aside that is not part of the main thread
//   ```fenced```    a command to type, which must not look like prose
//
// The first is inline, and is added by rewriting it as an HTML span — Qt does
// pass inline HTML through in markdown mode.
//
// The other two are blocks, and were originally done the same way. That was
// wrong: injecting a block-level <table> into markdown corrupts everything
// after it, an empty <td> aborts the parse outright, and a background colour
// silently refuses to paint on a bare <div>. All three were observed against
// the real widget. So blocks are split out here and drawn by QML instead,
// which also makes them themeable and independently selectable.

// ------------------------------------------------------------------ inline

// `==marked==` becomes a span the theme colours. Inline code is lifted out
// first: `==x==` between backticks is being shown to the reader, not applied.
function inline(raw, palette) {
  var pal = palette || {}
  var highlightBg = pal.highlightBg || "#b58900"
  var highlightFg = pal.highlightFg || "#101315"

  var spans = []
  var text = String(raw || "").replace(/`([^`\n]+)`/g, function (whole, code) {
    spans.push(code)
    return "SPAN" + (spans.length - 1) + ""
  })

  // One line break is allowed inside a highlight, because lesson source wraps
  // at 80 columns and a marked phrase routinely straddles the wrap. More than
  // one is refused: an unpaired `==` would otherwise swallow the rest of a page.
  text = text.replace(/==([^=\n]*(?:\n[^=\n]*)?)==/g, function (whole, marked) {
    // The line break inside a wrapped highlight has to become a space here:
    // once it is inside the span it is HTML, where a newline collapses to
    // nothing rather than to whitespace, welding the two words together.
    return '<span style="background-color:' + highlightBg +
      '; color:' + highlightFg + '">' + marked.replace(/\s*\n\s*/g, " ") + '</span>'
  })

  return text.replace(/SPAN(\d+)/g, function (whole, n) {
    return "`" + spans[Number(n)] + "`"
  })
}

// ------------------------------------------------------------------ blocks

// Callout kinds borrowed from Obsidian, relabelled for the reader. An unknown
// kind still renders, as a note, rather than leaking `[!whatever]` onto the page.
var CALLOUTS = {
  note:      { label: "Note",      tone: "accent" },
  tip:       { label: "Tip",       tone: "accent" },
  info:      { label: "Info",      tone: "accent" },
  important: { label: "Important", tone: "accent" },
  warning:   { label: "Careful",   tone: "urgent" },
  caution:   { label: "Careful",   tone: "urgent" },
  danger:    { label: "Stop",      tone: "urgent" },
  question:  { label: "Try it",    tone: "accent" },
  example:   { label: "Example",   tone: "accent" }
}

// Strip the wrapper a lesson file needs in order to stand alone elsewhere: the
// reader already draws the title from course.json, so a leading `# Title` would
// appear twice, and YAML frontmatter is metadata rather than content.
function unwrap(text) {
  text = String(text || "").replace(/^\uFEFF/, "")
  var frontmatter = text.match(/^---[ \t]*\r?\n[\s\S]*?\r?\n---[ \t]*\r?\n?/)
  if (frontmatter) text = text.slice(frontmatter[0].length)
  // One `# ` heading, only at the very top. `## ` is a real heading and stays.
  return text.replace(/^[\s]*#[ \t]+[^\n]*(\r?\n)+/, "")
}

// Returns [{ kind: "prose" | "code" | "callout", ... }] in document order.
//
//   prose    { kind, text }                  handed to Text.MarkdownText
//   code     { kind, language, text }        drawn as a code block
//   callout  { kind, label, tone, body }     drawn as an aside; body is prose
//
// Runs of ordinary markdown are kept together in one prose block rather than
// split per paragraph, so lists and tables — which span blank lines — survive.
function blocks(raw) {
  var lines = unwrap(raw).replace(/\r\n/g, "\n").split("\n")
  var out = []
  var buffer = []

  function flushProse() {
    var text = buffer.join("\n")
    if (text.replace(/\s/g, "") !== "") out.push({ kind: "prose", text: text })
    buffer = []
  }

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]

    var fence = line.match(/^[ \t]*```[ \t]*([A-Za-z0-9_+-]*)[ \t]*$/)
    if (fence) {
      var code = []
      var j = i + 1
      while (j < lines.length && !/^[ \t]*```/.test(lines[j])) { code.push(lines[j]); j++ }
      flushProse()
      out.push({
        kind: "code",
        language: fence[1] || "",
        text: code.join("\n").replace(/\s+$/, "")
      })
      // j is the closing fence, or the end of the file if it was never closed.
      i = j
      continue
    }

    var head = line.match(/^>[ \t]*\[!([A-Za-z]+)\][ \t]*(.*)$/)
    if (head) {
      var meta = CALLOUTS[String(head[1]).toLowerCase()] || CALLOUTS.note
      var body = []
      var k = i + 1
      while (k < lines.length && /^>/.test(lines[k])) {
        body.push(lines[k].replace(/^>[ \t]?/, ""))
        k++
      }
      flushProse()
      out.push({
        kind: "callout",
        label: head[2].replace(/\s+$/, "") || meta.label,
        tone: meta.tone,
        body: body.join("\n").replace(/\s+$/, "")
      })
      i = k - 1
      continue
    }

    buffer.push(line)
  }

  flushProse()
  return out
}
