# Rename

Convert files by renaming them.

Select a file in Finder, press Return, change `.png` to `.pdf`, and the file
becomes a real PDF. No upload, no website, no separate app to open. It works in
any folder, and a small notice confirms each conversion.

## What it converts

|              | to PNG | to JPEG | to TIFF | to GIF | to BMP | to HEIC | to PDF |
|--------------|:------:|:-------:|:-------:|:------:|:------:|:-------:|:------:|
| from PNG / JPEG / TIFF / GIF / BMP / HEIC | ● | ● | ● | ● | ● | ● | ● |
| from PDF     | ●      | ●       | ●       | ●      | ●      | ●       | –      |
| from WebP    | ●      | ●       | ●       | ●      | ●      | ●       | ●      |

A PDF of more than one page becomes a **`.zip` of numbered images** rather than
a single file, since one image cannot hold 100 pages. Rename asks first, and the
result is named `document.zip`, not the `document.jpg` you typed.

WebP can be read but not written — macOS has no WebP encoder — so renaming
something *to* `.webp` is refused rather than silently producing a broken file.

## Install

```bash
./Scripts/build-app.sh && open build
```

Drag `Rename.app` to `/Applications`, then launch it. It lives in the menu bar
with no Dock icon. Turn on **Launch at login** in Settings to keep it running.

macOS will ask for permission the first time it touches your Desktop, Documents,
or Downloads. Grant those, or it will silently skip files in exactly the folders
you use most.

## How it works

Renaming a file in Finder only changes its name — the bytes are untouched. So
Rename watches for rename events (via FSEvents), checks whether the file's real
format still matches its new extension, and re-encodes it when it doesn't.

Everything is decided from the file's **contents**, never its name. A text file
called `notes.jpg` is left alone; a PNG called `photo.jpg` is converted.

## Safety

- The original is copied to `~/Library/Application Support/Rename/Originals`
  before anything is overwritten, so any conversion can be undone from the menu.
  Copies are deleted automatically after a week.
- Only files whose new extension is one Rename understands are considered.
  System folders, caches, `node_modules`, `.git` and the Trash are skipped.
- A rename that doesn't change the format (`.jpg` → `.jpeg`) does nothing.

## Development

```bash
swift test              # engine tests
swift build             # library, CLI, and app binary
./Scripts/build-app.sh  # assemble and sign Rename.app
```

`renamectl` is a command-line front end to the same engine, useful for testing
without the UI:

```bash
.build/debug/renamectl inspect photo.jpg    # what is it really?
.build/debug/renamectl plan photo.jpg       # what would converting do?
.build/debug/renamectl convert photo.jpg    # do it
.build/debug/renamectl watch ~/Desktop      # react to renames in a folder
```

Set `RENAME_DEBUG=1` to print raw filesystem events.

### Layout

- `Sources/ConvertKit` — format detection, planning, conversion, watching. No UI.
- `Sources/RenameApp` — the menu-bar app.
- `Sources/renamectl` — command-line front end.
