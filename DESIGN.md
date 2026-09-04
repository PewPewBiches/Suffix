# Suffix — design language

One set of decisions, used by the icon, the app, the notices and the website.
If something looks off, it is probably ignoring this file.

## The idea

Suffix is a selected file whose extension is being edited. Everything visual
comes from that one picture, not from a mood board.

Two devices carry it:

**The selection block.** A filled rectangle in selection blue with white text,
exactly like a highlighted filename in Finder. This is the *only* emphasis
device. No underlines, no coloured text, no bold-as-highlight.

**The extension chip.** A monospace `.pdf` in a small rounded rectangle. Used
wherever a destination format is named.

Everything else is a file list: rows, columns, hairlines, and aligned data.
Cards are a last resort — a file browser has rows, not cards.

## The world

System 7, done properly rather than gestured at. Chicago for chrome, Geneva for
reading, pinstriped title bars, 1px black frames, the 50% dither desktop, and
the 1984 pointer as the cursor.

It is not black and white: the six-colour Apple logo is the palette. Green,
yellow, orange, red, purple, blue appear as the divider rule, the document
icons, and the alert badge — the way System 7 itself used colour, sparingly and
on objects rather than on text.

## Colour

| Token | Light | Dark | For |
|---|---|---|---|
| `ink` | `#0E0F12` | `#EDEDEA` | text |
| `paper` | `#F7F7F5` | `#0D0E10` | page |
| `surface` | `#FFFFFF` | `#16171A` | rows, panels |
| `line` | `#E3E2DD` | `#26282C` | hairlines |
| `muted` | `#6C6A64` | `#9A978F` | secondary text |
| `faint` | `#A5A29A` | `#6A6862` | labels, captions |
| `select` | `#0B62F6` | `#3D8BFF` | the selection block, and nothing else |
| `good` | `#1F7A4C` | `#4FBE86` | a conversion that worked |
| `warn` | `#A8570F` | `#E0964A` | approximate results, missing encoders |

One accent. `select` is not decoration — it means *this is the thing being
acted on*. Using it anywhere else weakens every place it is used correctly.

## Type

| Role | Face | Notes |
|---|---|---|
| Display | **Martian Mono** | Wordmark and headlines. Monospace, because the product is about filenames. Tight tracking, lowercase. |
| Interface | **Schibsted Grotesk** | Body, labels, buttons. |
| Data | **IBM Plex Mono** | Filenames, extensions, sizes, code. |

In the app, Interface is the system font — a Mac utility should use the system
face. Display and Data still apply to the wordmark and to filenames.

Headlines are lowercase. Sentence case everywhere else. Never all-caps except
column labels, which are 10–11px with wide tracking.

## Layout

- A file list fills its container. Content does not sit in a narrow column with
  empty margins — that is a document, not a product page.
- Reading text caps at ~70ch, but it sits inside a wider grid alongside data,
  not alone in the middle of the screen.
- Columns align across sections. Rows are 1px-separated, not boxed.
- Radius: 6px for chips and rows, 10px for panels, 22.37% for the app icon.

## Motion

One idea: a rename happening. Type, select, convert. Everything else is still.
Nothing floats, bobs, or drifts — a file browser does not wobble.

Honour `prefers-reduced-motion` by showing the finished state.

## Voice

Lowercase headlines. Plain sentences. Say what the thing does and what it costs.

- Name the mechanism, not the benefit: “reads the words in the image”, not
  “unlock your content”.
- State limits in the same breath as the feature. If a conversion is
  approximate, the sentence that offers it says so.
- No exclamation marks. No “simply”, “just”, “effortlessly”, “seamless”.
- Errors say what happened and what to do: “macOS cannot write MP3 — install
  ffmpeg”, never “something went wrong”.

## The icon

A dark rounded square. A white monospace period, then a selection-blue block —
the dot and the highlighted extension after it. Two shapes, so it still reads
at 16px.
