# Elementary

An Omarchy shell plugin: a reading window for learning to use the computer,
meant to sit tiled beside the terminal you are learning to use.

The plugin is only the frontend. The curriculum is a separate git repo you own,
fork, or point at a folder on your own disk — so the software and the teaching
can be changed by different people at different times.

```
┌──────────────────────┬──────────────────────┐
│  Elementary          │  $ cd ~/arduino      │
│                      │  $ ls                │
│  Basics        6/9   │  blink.ino           │
│   ✓ The Mouse        │  $ █                 │
│   · Filenames        │                      │
│                      │                      │
│  [‹ Back] [Next ›]   │                      │
└──────────────────────┴──────────────────────┘
```

## What it does

- Renders a markdown curriculum from a git repo, one lesson at a time —
  headings, emphasis, lists, tables and links, plus `==highlights==`,
  `> [!callouts]`, and code blocks on their own selectable surface.
- Remembers what has been read, and where you left off.
- Shows progress in the bar; click it to open the reader.
- Nothing is locked. Progress is a record, not a gate — everything is
  browsable from the first day.

## Install

Two commands. The first installs the reader, the second tells it what to read:

```bash
omarchy plugin add https://github.com/gig3m/omarchy-elementary.git --enable --yes
omarchy bar set elementary curriculum https://github.com/gig3m/elementary-curriculum.git
```

The curriculum is cloned on the next check and the reader picks it up without a
restart. Click the bar widget, or bind a key to `omarchy-shell elementary open`.

Requires Omarchy with `omarchy-shell`, and `git` for a URL source.

### Reading your own course

Fork [elementary-curriculum](https://github.com/gig3m/elementary-curriculum),
or start an empty repo with a `course.json` at its root, and set `curriculum` to it:

```bash
omarchy bar set elementary curriculum https://github.com/you/your-curriculum.git
```

### Writing lessons

Point `curriculum` at a folder instead of a URL. A local path is read in place and
never pulled, so each save shows up in the reader immediately:

```bash
git clone https://github.com/you/your-curriculum.git ~/Projects/my-curriculum
omarchy bar set elementary curriculum ~/Projects/my-curriculum
```

### Hacking on the plugin

```bash
git clone https://github.com/gig3m/omarchy-elementary.git ~/Projects/elementary
ln -s ~/Projects/elementary ~/.config/omarchy/plugins/elementary
omarchy plugin validate ~/.config/omarchy/plugins/elementary
omarchy-shell shell rescanPlugins
omarchy plugin enable elementary
```

Editing a file under `~/.config/omarchy/plugins/` hot-reloads plugin code, but
a panel that is already open keeps its old component — run
`omarchy-restart-shell` after changing the reader window itself.

**Reserved setting keys.** A bar layout entry carrying `source`, `exec`, or
`type` is claimed by the bar as a *custom module*
([`BarModel.customModuleType`](https://github.com/basecamp/omarchy)), which
discards the registered plugin widget and tries to load the value as a QML
file. The widget then silently never appears — no error, and the plugin's
service and panel keep working, so it looks like a rendering bug rather than a
name collision. This plugin's curriculum setting is called `curriculum` for
exactly that reason.

### Uninstall

```bash
omarchy plugin disable elementary     # off the bar, code left in place
omarchy plugin remove elementary      # and gone
```

Progress in `~/.local/state/elementary/` survives both; delete it to start over.

The full content contract is in [docs/content-format.md](docs/content-format.md).

## Settings

| Setting | Default | Meaning |
|---------|---------|---------|
| Curriculum | — | Git URL, or a folder on this machine |
| Branch | `main` | Only used for git URLs |
| Pull new lessons automatically | On | Fast-forward only; offline keeps working |
| Check for new lessons every | 60 min | |
| Reading size | Large | Body text size in the reader |

## Keyboard

| Key | |
|-----|---|
| `→` / `PgDn` | Next lesson |
| `←` / `PgUp` | Previous lesson |
| `Esc` | Close the window |

## IPC

```bash
omarchy-shell elementary open      # open the reader
omarchy-shell elementary resync    # pull the curriculum now
omarchy-shell elementary status    # JSON: path, sync mode, lessons read
```

## Where things live

| Path | What |
|------|------|
| `~/.local/share/elementary/curriculum` | Cloned curriculum (git-URL sources only) |
| `~/.local/state/elementary/progress.json` | What has been read, and where you left off |
| `~/.config/omarchy/shell.json` | The plugin's settings, inline on its entry |

Progress is deliberately outside the curriculum repo: pulling new lessons never
conflicts with having read the old ones, and forking a course inherits its
lessons but not someone else's checkmarks.

## Layout

| File | |
|------|---|
| `Service.qml` | Owns the curriculum on disk and the progress record |
| `BarWidget.qml` | Progress in the bar; opens the reader |
| `App.qml` | The reader window |
| `Curriculum.js` | Pure model: parse, order, progress arithmetic |
| `Markdown.js` | Pure model: splits a lesson into prose / code / callout blocks |
| `Progress.js` | Pure model: the read record |
| `scripts/curriculum-sync.sh` | Resolves a source to a directory on disk |
| `scripts/state-store.sh` | The plugin's only write path, atomic |

The curriculum lives in its own repo, not here: the software and the teaching
change at different rates and by different hands.

The three `.js` files are pure and do no I/O, so the rules about what a course
*is* — and how a lesson is cut into blocks — can be tested without a shell
running.

## Licence

MIT.
