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

```bash
omarchy plugin add https://github.com/gig3m/omarchy-elementary.git --enable --yes
```

Or, to work on it locally:

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/elementary
omarchy plugin validate ~/.config/omarchy/plugins/elementary
omarchy-shell shell rescanPlugins
omarchy plugin enable elementary
```

Saving any file under `~/.config/omarchy/plugins/` hot-reloads the plugin, so
the symlink is the whole dev loop.

## Point it at a curriculum

Open the bar widget's settings and set **Curriculum source** to a git URL, or
to a folder on this machine. A local folder is read in place and never pulled —
that is the path for writing lessons, and the reader picks up each save
immediately.

[elementary-curriculum](https://github.com/gig3m/elementary-curriculum) is the
reference course — five sections, twenty-two lessons, aimed at a child moving
off an iPad. Point the setting straight at it:

```
https://github.com/gig3m/elementary-curriculum.git
```

To write your own, fork that repo (or start an empty one with a `course.json`),
clone it, and point the setting at the clone's path — a local folder is read in
place, so each save shows up immediately.

The full content contract is in [docs/content-format.md](docs/content-format.md).

## Settings

| Setting | Default | Meaning |
|---------|---------|---------|
| Curriculum source | — | Git URL, or a folder on this machine |
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
