# REname

**Convert files by renaming them.**

Select a file in Finder, press Return, change `.png` to `.pdf`, and the file
becomes a real PDF. No upload, no website, no app to open. It works in every
folder on your Mac, and a small card confirms each conversion with an Undo
button.

---

## Install

Download `REname.dmg` from [Releases](../../releases), drag REname to your
Applications folder, and open it.

### The first time you open it

REname isn't signed with a paid Apple Developer certificate, so macOS will
refuse to open it and say it "cannot be verified". This is Gatekeeper reacting
to the missing $99/year signature, not to anything the app does.

To open it anyway:

1. Try to open REname. Let macOS block it.
2. Go to **System Settings → Privacy & Security**.
3. Scroll down. There's a line about REname being blocked — click **Open Anyway**.

You only do this once. If you'd rather not trust a stranger's build, the whole
app is here — clone it and run `./Scripts/build-app.sh` to build your own.

### Give it access to your files

macOS protects Desktop, Documents and Downloads. Without access REname keeps
running but silently does nothing in exactly the folders you use most, so the
setup window asks for **Full Disk Access** and then offers a **Test it** button
that converts a real file to prove the whole chain works.

Don't skip the test. A silent, healthy-looking failure is this app's
characteristic way of going wrong.

---

## What it converts

|                                            | PNG | JPEG | TIFF | GIF | BMP | HEIC | PDF |
|--------------------------------------------|:---:|:----:|:----:|:---:|:---:|:----:|:---:|
| **from** PNG / JPEG / TIFF / GIF / BMP / HEIC | ●   | ●    | ●    | ●   | ●   | ●    | ●   |
| **from** PDF                                | ●   | ●    | ●    | ●   | ●   | ●    | –   |
| **from** WebP                               | ●   | ●    | ●    | ●   | ●   | ●    | ●   |

A PDF of more than one page becomes a **`.zip` of numbered images** rather than
a single file, because one image cannot hold 100 pages. REname asks first, and
names the result `document.zip` rather than the `document.jpg` you typed.

WebP can be read but not written — macOS ships no WebP encoder — so renaming
something *to* `.webp` is refused rather than half-done.

---

## Replace, or keep both

Set during setup, changeable any time in Settings:

| | After renaming `photo.png` to `photo.pdf` |
|---|---|
| **Replace the file** | `photo.pdf` — one file, as renaming implies. Undo for 7 days. |
| **Keep both** | `photo.pdf` and `photo.png`, side by side in the same folder. |

Either way the original is copied aside before anything is overwritten, and any
conversion can be undone from the menu bar for seven days.

---

## How it works

Renaming a file in Finder only changes its name — the bytes are untouched. So
REname watches for rename events through FSEvents, checks whether the file's
real format still matches its new extension, and re-encodes it when it doesn't.

Everything is decided from the file's **contents**, never its name. A text file
called `notes.jpg` is left alone; a PNG called `photo.jpg` is converted.

Conversion uses only what ships with macOS — ImageIO, PDFKit, Core Graphics.
No bundled binaries, no network access. REname never sends your files anywhere,
because it has nowhere to send them.

---

## Development

```bash
swift test                                    # engine tests
./Scripts/build-app.sh                        # assemble REname.app
build/REname.app/Contents/MacOS/REname --render-previews /tmp/ui
```

That last one renders every screen to PNG in both light and dark, which is how
the interface gets reviewed without a screen recording.

`renamectl` drives the same engine from the command line:

```bash
.build/debug/renamectl inspect photo.jpg    # what is it really?
.build/debug/renamectl plan photo.jpg       # what would converting do?
.build/debug/renamectl convert photo.jpg    # do it
.build/debug/renamectl watch ~/Desktop      # react to renames in a folder
```

`RENAME_DEBUG=1` prints raw filesystem events.

### Layout

| Path | What's in it |
|---|---|
| `Sources/ConvertKit` | Format detection, planning, conversion, watching. No UI. |
| `Sources/RenameApp` | The menu-bar app. |
| `Sources/renamectl` | Command-line front end. |

### Notes for anyone touching the watcher

Three FSEvents behaviours cost real debugging time here:

- **`kFSEventStreamCreateFlagUseCFTypes` is mandatory.** Without it the callback
  receives a C `char**`, and reading it as a `CFArray` is silently wrong.
- **`FSEventStreamSetExclusionPaths` returns `true` and then suppresses every
  event** on a file-level stream. Directory filtering is done in Swift instead.
- **A rename can arrive as `Removed | Renamed` in one coalesced event.**
  Filtering out `Removed` drops real renames. Existence on disk is the reliable
  test of which name survived.

All three present identically: a watcher that looks healthy and does nothing.
Test watcher changes in a busy folder through Finder, not with `mv` in an empty
directory — a quiet folder never reproduces the coalescing.
