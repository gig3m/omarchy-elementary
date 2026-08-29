# The content repo

Elementary renders a curriculum it does not own. The curriculum is an ordinary
git repo — public, private, or a fork of someone else's — and this file is the
whole contract between the two.

The reference course is
[elementary-curriculum](https://github.com/gig3m/elementary-curriculum). Fork
it, or start an empty repo with a `course.json` at its root.

## Layout

```
course.json          required, at the repo root
basics/01-mouse.md   lesson bodies, anywhere you like
basics/06-filenames.md
cli/01-what-a-terminal-is.md
```

Only `course.json` has a required location. Lesson files live wherever the
paths in `course.json` say they do.

## course.json

```json
{
  "title": "Learning the Computer",
  "sections": [
    {
      "id": "basics",
      "title": "Basics",
      "summary": "The floor everything else stands on.",
      "lessons": [
        { "id": "mouse", "title": "The Mouse", "file": "basics/01-mouse.md" }
      ]
    }
  ]
}
```

| Field | Required | Notes |
|-------|----------|-------|
| `title` | no | Shown as the window title. Defaults to "Curriculum". |
| `sections[].id` | **yes** | Stable identifier. Half of a lesson's progress key. |
| `sections[].title` | no | Falls back to the id. |
| `sections[].summary` | no | One line. Not shown in the reader yet. |
| `lessons[].id` | **yes** | Stable identifier, unique within its section. |
| `lessons[].title` | no | Falls back to the id. |
| `lessons[].file` | **yes** | Path relative to the repo root. |

Sections and lessons are rendered in array order. That order *is* the reading
order — there is no separate sequencing field, and no prerequisites.

### Ids are the thing you must not churn

A lesson's progress is stored under `"<section id>/<lesson id>"`. That key is
deliberately not the filename, so you can rename `01-mouse.md` to
`01-the-mouse.md`, reorder a section, or rewrite a lesson from scratch without
throwing away the fact that someone already read it.

Changing an `id`, by contrast, silently resets that lesson to unread. Treat ids
as permanent once anyone has read the course.

Duplicate ids are dropped rather than merged — two lessons sharing a key would
let one mark the other read.

## Lesson files

Plain markdown. Keep a lesson short enough to read in one sitting without
scrolling forever — the reader shows one at a time, and "Mark as read" moves
straight on to the next.

If a file opens with a `# Title`, that heading is dropped: the reader already
draws the title from `course.json`, so it would otherwise appear twice. YAML
frontmatter is dropped for the same reason. Both are kept in the file so a
lesson still reads correctly on GitHub or in Obsidian.

### What renders

| Syntax | |
|--------|---|
| `# ## ###` | Headings |
| `**bold**` `*italic*` `~~struck~~` | Emphasis |
| `` `code` `` | Inline code |
| `- item`, `1. item` | Lists, including nested |
| `\| a \| b \|` | Tables |
| `> quoted` | Block quote |
| `[text](url)` | Link — opens in the system browser |
| `==marked==` | **Highlight.** Painted in the theme's accent |
| ```` ```lang ```` | **Code block.** Its own surface, and selectable |
| `> [!kind] Title` | **Callout.** An aside with a coloured bar |
| `![alt](path)` | **Picture.** On a line of its own; alt becomes the caption |

The last three are extensions on top of what Qt renders natively. Highlights
may straddle one line break, so a marked phrase can wrap normally in the
source; two breaks is treated as an unpaired `==` and left alone.

Callout kinds, borrowed from Obsidian. An unrecognised kind renders as a note
rather than leaking `[!whatever]` onto the page:

| Kind | Shows as | Tone |
|------|----------|------|
| `note` `info` `tip` `important` | Note / Info / Tip / Important | accent |
| `question` | Try it | accent |
| `example` | Example | accent |
| `warning` `caution` | Careful | urgent |
| `danger` | Stop | urgent |
| `machine` | On your computer | neutral |

The text after the kind replaces that label, so `> [!warning] Leave the
extension alone` is titled with the sentence rather than "Careful".

`machine` exists for a course that teaches both how computers work in general
and how one particular machine works. Keep the general idea in the prose and
the specific keystroke in the box; on a different machine, the boxes are
exactly what needs rewriting.

A `>` quote with no `[!kind]` stays an ordinary block quote.

### Pictures

`![alt text](../images/thing.png)` on a line of its own. The path is relative
to the lesson file, as in any other markdown tool, so the same file renders
here, on GitHub, and in Obsidian. Absolute paths and `https://` URLs also work.

An image is only recognised on a line of its own — inside a paragraph it stays
in the prose, where Qt drops it. Alt text becomes a caption under the picture.
A picture that cannot be found says so, naming the path, rather than leaving a
gap.

Pictures are never scaled up past their own resolution.

### What does not render

Raw HTML, footnotes, and `[[wikilinks]]`. Colours always come from the active
Omarchy theme, so a lesson never sets one.

## Pointing the plugin at a repo

In the bar widget's settings, set **Curriculum** to either:

- a git URL — cloned once into `~/.local/share/elementary/curriculum`, then
  fast-forwarded on the schedule set by **Check for new lessons every**; or
- a path to a folder on this machine — read in place and never pulled.

The local-folder path is the authoring path. Save a lesson, and the reader
picks it up immediately: both `course.json` and the open lesson file are
watched.

If the network is down, a repo that was cloned earlier keeps working — the
sync reports itself stale and the reader carries on with what it has.

## What the content repo never contains

Progress. It lives in `~/.local/state/elementary/progress.json` on each
machine, so pulling new lessons can never conflict with having read the old
ones, and forking a course inherits its lessons but not someone else's
checkmarks.
