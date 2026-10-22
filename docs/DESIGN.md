# mpv-redesigned — site design system

This is the contract. Every section of the site is built from it, and no
section may invent a colour, a typeface, a radius or a grid split of its own.

---

## 1. The idea

**The site is the printed front matter of a service manual for a video
player.**

The product ships with `docs/INSTALL.md`, `docs/FEATURES.md`,
`docs/KEYBINDINGS.md` and `docs/ARCHITECTURE.md`. Its community reads
`man mpv`. A tuned mpv configuration is an *artifact*, and an artifact gets a
spec sheet, not a hero video. So the page is a document: numbered sections,
numbered figures, measured claims set in the margin, hairline rules instead
of boxes, and one dark plate where the product itself is shown.

Two things make this specific rather than generic:

- **The margin band.** Every section carries its folio and its measured
  claims in a column down the left edge of the page: `0 dropped frames`,
  `PSNR ≥ 66.5 dB`, `13 scripts`, `~60 MB`. Those numbers are real, they come
  out of the repository's own README, and they are the proof. No generator
  invents them.
- **The dark plate.** The document is paper, and once — in the showcase —
  it opens into a dark inspection bay where the four skins are turning on a
  light table. Paper and dark, once each.

### What this must never become

Dark ground with a neon gradient. Rounded glass cards. A centred hero with a
gradient word. A tracked-out uppercase label above every heading. Twelve
identical feature tiles. Icons in a grid. A particle starfield. `Inter`.
`Instrument Serif`. Playfair. Fraunces. Space Grotesk. Anything with a
`rounded-xl` and a `backdrop-blur`.

---

## 2. Palette

Six tones and one accent. Paper is a cool neutral grey, deliberately *not*
cream — cream paper with a serif is the single most recognisable generated
page.

| token | hex | role |
|---|---|---|
| `--paper` | `#E7E8E4` | the page |
| `--paper-soft` | `#DFE0DA` | inset panels, table banding |
| `--paper-deep` | `#D5D6D0` | pressed states |
| `--ink` | `#16171A` | body text, headings, dark plate ground |
| `--ink-2` | `#33363B` | secondary text |
| `--ink-3` | `#5A5E63` | muted text, marginalia |
| `--rule` | `#C3C4BD` | hairlines (decorative only) |
| `--rule-soft` | `#D3D4CE` | the lighter hairline, table rows |
| `--signal` | `#BC3A1E` | the one accent: the scrubber, the primary button, the folio |
| `--signal-deep` | `#942C15` | the accent as small text, where `--signal` has no headroom |
| `--plate` | `#131416` | the dark plate |
| `--plate-2` | `#1E2023` | the dark plate, one step up |

Measured contrast on `--paper`: ink **14.1:1**, ink-2 **9.5:1**,
ink-3 **5.3:1**, signal **4.5:1**, signal-deep **6.5:1**. Paper on `--plate`
**14.7:1**. Signal is never used as small text: on `--paper-soft` it is only
4.2:1, so anything the reader has to read is set in `--signal-deep`. Nothing
on this page may be set in signal on the dark plate — it would be 2.7:1.

**Signal does four things:** the folio, the scrubber at the top of the
window, the one primary button, and the numbers that count things — the
twelve-item index and the figure numbers. It is never a background wash,
never a gradient, and never a bullet. A marker repeated eighteen times is
decoration, not an accent.

---

## 3. Type

```
https://fonts.googleapis.com/css2?family=Archivo:wdth,wght@62..125,100..900&family=Bodoni+Moda:ital,opsz,wght@0,6..96,400..900;1,6..96,400..900&family=IBM+Plex+Mono:wght@400;500;600&display=swap
```

- **Bodoni Moda** — headings only. A didone is the language of film titles;
  nothing else on the page uses it. Never below 24 px, never on the dark
  plate, never in a table.
- **Archivo** — everything a person reads as prose: standfirsts, body,
  buttons, navigation.
- **IBM Plex Mono** — everything a machine reads: folios, file paths, config,
  key names, numbers, captions. Tabular figures everywhere.

| role | family | size | line-height | measure |
|---|---|---|---|---|
| masthead | Bodoni Moda | `clamp(3rem, 6.4vw, 6.1rem)` | 0.94 | — |
| section headline | Bodoni Moda | `clamp(1.9rem, 4vw, 3.25rem)` | 1.04 | 20ch |
| subhead | Bodoni Moda | `clamp(1.3rem, 1.9vw, 1.75rem)` | 1.18 | 24ch |
| standfirst | Archivo 400 | `clamp(1.05rem, 1.25vw, 1.22rem)` | 1.5 | 46ch |
| body | Archivo 400 | 1rem | 1.62 | 66ch |
| folio / label | Plex Mono 500 | 0.72rem, `letter-spacing .14em`, uppercase | 1.4 | — |
| data / code | Plex Mono 400 | 0.84rem | 1.55 | — |

Headings are left aligned with a ragged right. Never centred. A heading is
never set below 24px, and the serif is never used inside a table.

---

## 4. Grid

One grid for the whole page.

- 12 columns, 2rem gutters, max width 90rem, side padding 1.25 / 2 / 3rem.
- At ≥1200px there is a **margin band**: 9rem of column to the left of the
  12-column field, carrying the folio. The field's left edge and the band's
  right edge are the same line on every section.
- Standard section head: **headline in columns 1–6, standfirst in 7–12**,
  both starting on the same line. The FAQ follows the same head and puts
  its answers in a full width band below it.
- Three figure widths only: **12** (full bleed), **8** (the configuration
  tree, with 4 columns of marginalia), and **6/6**.

Every section opens with the same block: a hairline, the folio in the band,
the headline, and the standfirst.

---

## 5. The parts

| class | what it is |
|---|---|
| `.folio` | the number and running title in the margin band |
| `.folio-num` | the number, in signal |
| `.section-head` | the hairline + headline + standfirst block |
| `.kicker` | mono uppercase label |
| `.plate` | a framed figure with a caption bar under it |
| `.plate-cap` | the caption, mono |
| `.dark-plate` | the full-bleed dark band |
| `.cmd` | a command block: ink ground, paper mono, signal left bar |
| `.tbl` | a hairline table, no boxes, tabular figures |
| `.note` | a marginal note, mono, ink-3 |
| `.measured` | a measured claim in the margin, mono, signal for the number |
| `.rule` / `.rule-strong` | hairline / ink hairline |
| `.index-row` | one row of the twelve-item index |
| `.qa` | a question and its answer |

Rules of the house: **no border radius above 2px, no box shadow, no blur, no
gradient, no glow.** Hierarchy comes from rules, weight, size and space.

---

## 6. Order and numbering

The order is the reading order, and it changed: the product is a *skin*, so
the pictures come before the claims.

1. **Hero** — masthead, one command, four numbers.
2. **Showcase** — `01` — the dark plate and the four stills.
3. **What you get** — `02` — the index of twelve.
4. **Inside the configuration** — `03` — the tree.
5. **Deep dive** — `04` — six articles with real config.
6. **Key bindings** — `05` — the table.
7. **Install** — `06` — the procedure.
8. **FAQ** — `07` — the trust questions.

Figures are `PLATE 01`–`PLATE 04`. Deep dive snippets are `FIG. 04.1`–
`FIG. 04.6`. Feature rows are `01`–`12`. Key binding groups are `5.1`–`5.8`.

---

## 7. Non-negotiables

1. Section ids stay: `top`, `showcase`, `features`, `inside`, `deep`,
   `keys`, `install`, `faq`. The scroll spy and the nav depend on them.
2. Every `[data-spy]` value must equal a section id.
3. Tab button order must equal tab panel order, and `x-show` must equal the
   button index.
4. Every copy button keeps `[data-copy]` **and** a `[data-copy-label]` child.
5. The Alpine component names stay: `siteNav`, `tabSet`, `bindingsPanel`.
6. The plain fallbacks must be styled by `main.css` alone — they may not
   depend on a Tailwind utility.
7. No `text-white/` or `bg-white/` anywhere: on paper, white is invisible.
   The build fails if one appears.

---

## 8. Assets

Four stills live in `site/assets/images/`. Each one is a capture of the
shipped configuration, and the name says what the frame shows.

| file | what it shows |
|---|---|
| `hero-idle.png` | the idle screen: a fetched photograph behind the "Welcome / Drop a file or link to play" prompt |
| `control-bar.png` | the Liquid Glass control bar drawn over a playing frame |
| `format-picker.png` | the format picker: the formats the server actually offers |
| `load-media-menu.png` | the load-media browser: a search field and a result list, in the player's own type scale |

**The rule.** A published screenshot may never contain a local path, a
terminal window or a chat window — it is a picture of the product and
nothing else. A grep cannot read pixels, so the rule is enforced by
hand, at publish time, as the first item of this checklist.

**Publishing checklist.** Before a still goes on the page:

1. The frame shows the player and nothing else — no terminal window, no
   chat window, no file manager, no desktop.
2. No local path, user name or home directory is legible anywhere in the
   frame.
3. The caption says what is on screen, in the same words the section
   around it uses.
4. The file name says what the frame shows; the four names above are the
   four that exist, and an old name is never left behind in the markup.
5. The still is a capture of the shipped configuration, not a drawing.

