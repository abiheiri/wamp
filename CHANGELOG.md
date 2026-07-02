# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed

- **Idle CPU usage while paused or stopped.** The spectrum analyzer kept
  redrawing at 60fps after the bars had decayed, the audio engine's render
  thread kept pulling silence while paused or stopped (including pausing a
  radio stream, which routes to stop), and the LCD marquee re-measured its
  text 30 times a second. The analyzer timer now stops once the display is
  empty, the engine pauses with playback, and the marquee timer only runs while
  a too-wide title is actually scrolling (still scrolling while paused, like
  classic Winamp).

## [1.2.5] - 2026-07-01

### Added

- **Favorite the now-playing radio station.** A station played from the
  Cmd+J finder can now be saved even though it isn't in any list: right-click
  it (or ⌘D) in the finder, or use the GENRE menu's "★ Add current" item. The
  currently-playing station is also marked with a ▶ in the radio list.

### Fixed

- **Hardened rapid radio-station switching against races.** Quickly switching
  stations could let an earlier, slow-to-resolve pick override a later one, and
  a previous stream's late (cancelled) callbacks could disturb the current
  stream. A superseded-click guard and a per-stream generation token now ensure
  only the latest pick plays and stale stream callbacks are ignored.

### Changed

- **MISC ▸ Jump to File is a prompt in both sections.** On the playlist it
  filters the local list (restored in every mode); on the Radio tab it now
  searches all of SHOUTcast and shows the results in the panel, like the
  inline search bar.

## [1.2.4] - 2026-06-28

### Added

- **Windowshade mode.** A new title-bar button (and View → Windowshade, or
  Cmd+Shift+W) rolls the whole window up to a compact title strip that keeps a
  scrolling track title, a time readout, and a mini seek bar — click again to
  restore the full player. Works skinned and unskinned, and the collapsed
  state is remembered across launches. The title-bar buttons are now ordered
  minimize / windowshade / close to match classic Winamp.

- **Hide Wamp with Cmd+H.** The app menu now has a "Hide Wamp" item bound to
  the standard macOS Cmd+H shortcut.

### Fixed

- **Update alert no longer repeats the version.** "Check for Updates…" showed
  the new release name/version twice (once in the title, once in the body).
  The redundant release-name line is gone.

## [1.2.3] - 2026-06-26

### Added

- **Jump-to (Cmd+J) now has Playlist and Radio tabs.** The finder opens on
  the section you're viewing. The Playlist tab filters local tracks as
  before; the new Radio tab searches the entire SHOUTcast directory (a
  debounced network search) and plays the picked station. The search is
  ephemeral — it doesn't disturb the genre list you were browsing in the
  panel. On the Radio tab, the playlist MISC ▸ Jump to File item opens this
  same directory search instead of the local-only filter.

- **Favorite SHOUTcast stations.** Right-click any station to add or remove
  it from a saved favorites list that persists across launches. A
  "★ Favorites" entry at the top of the genre menu opens them for quick
  access, so stations you like aren't lost between genre browses.

### Fixed

- **Skinned playlist filter can now be cleared.** Using MISC ▸ Jump to File
  in skinned mode filtered the list with no visible way to reset it. The
  MISC menu now shows a "Clear Filter (showing N of M)" item whenever the
  active section (playlist or radio) is filtered, which restores the full
  list.

## [1.2.2] - 2026-06-26

### Added

- **60 fps spectrum analyzer with gravity peaks.** The visualization now
  animates smoothly on its own timer instead of jumping with each audio
  buffer, with fast attack / slow decay bars and falling peak caps that
  hold briefly before accelerating downward — closer to classic Winamp.

### Fixed

- **Skin scaling artifacts on Retina displays.** All skin sprite drawing
  now disables antialiasing, sets nearest-neighbor interpolation, and
  pixel-snaps every rect to physical backing pixels. Playlist top/side
  tiling is edge-to-edge so seams no longer appear at fractional scales,
  and the main window region mask renders at the display's backing scale.

- **Skinned LCD title is clean and placeholders are explicit.** In skinned
  mode the scrolling title shows only the track name (the playlist and
  7-segment display already show number and duration). Missing bitrate /
  sample rate now render as `---` / `--` instead of blank space, and the
  title re-formats immediately when a skin is loaded or unloaded.

- **Bitrate no longer reads 0 for FLAC, WAV, AIFF, and some VBR MP3s.**
  When `AVAssetTrack.estimatedDataRate` returns 0, Wamp now falls back to
  `fileSize * 8 / duration` so the kbps display works for those formats.

- **Small system fonts render cleanly on macOS.** The previous Tahoma /
  ArialMT fallbacks aren't shipped with macOS and fell through to a poorly
  hinted substitute. Fonts now use SF Pro system APIs (including monospaced
  digits for bitrate), which are readable down to 6 pt.

- **Menu bar shows real titles instead of "NSMenuItem".*** The top-level
  menus were created without titles, so AppKit displayed the class name.
  They now read **Wamp**, **File**, **Edit**, **Controls**, and **View**.

### Added

- **Check for Updates** under the Wamp menu. The app queries GitHub Releases
  for the latest tag, compares it to the running version, and shows an alert
  with release notes plus an "Open Releases Page" button when a newer version
  is available.

### Changed

- **Repository URLs now point to `abiheiri/wamp`.** The README clone URL,
  the About panel link, and the main-player GitHub hit-zone were still
  referencing the original `wishval/wamp` fork.

## [1.2.1] - 2026-06-26

### Fixed

- **High idle CPU usage.** After playback stopped, the spectrum analyzer
  kept running its FFT on silence (the audio tap was never removed), and
  the LCD marquee redrew at 30fps even when its text wasn't scrolling.
  Both now go quiet when nothing is playing, dropping idle CPU sharply.
- **Spectrum analyzer rebuilt its FFT setup on every audio buffer.** It is
  now created once and reused while playing (rebuilt only if the analysis
  size changes), trimming CPU during playback. The bars are unchanged.

## [1.2.0] - 2026-06-26

### Added

- **SHOUTcast internet radio, merged into the playlist panel.** A
  `PLAYLIST | RADIO` tab in the playlist lets you browse stations by
  genre or search and play them through the full audio pipeline
  (10-band EQ, volume, balance) — the local playlist stays separate.
  Playback is driven entirely by the main transport buttons: play/stop
  control the stream, and next/previous step through the station list.
  Genres are pulled live from the directory as a main/sub tree (cached to
  disk, with a bundled fallback when offline), the station list shows
  listener counts, and an empty-state row guides you when nothing has
  loaded.
  The LCD marquee shows the live ICY "now playing" title. (The standalone
  SHOUTcast Radio window has been removed in favour of this.)

## [1.1.0] - 2026-06-25

### Added

- **Mini-transport buttons in the skinned playlist are now interactive.**
  The five baked buttons (prev / play / pause / stop / next) in
  pledit.bmp's bottom-right corner now respond to clicks and route
  through the same `AudioEngine` + `PlaylistManager` calls as the main
  transport bar — including "load-and-play" when triggered from a
  stopped state. Same role they had in classic Winamp 2.x.

- **EJECT button in the playlist BR corner now opens "Play file…"** —
  the sixth baked button (the "▲" sprite) routes to the same
  `NSOpenPanel` as `File ▸ Open File…` / Cmd+O.

### Fixed

- **Loaded skin no longer forgotten after changing volume and quitting.**
  Debounced state saves rebuilt `state.json` from defaults, wiping
  `skinPath` (and window position fields) on every volume/EQ change.
  Saves now start from the persisted state.

- **UTF-8 `.m3u` playlists with non-ASCII paths now load.** Decoding
  tried Latin-1 first for `.m3u` — which succeeds for any bytes — so
  UTF-8 content turned into mojibake and tracks went missing. Strict
  UTF-8 is now tried first, then CP-1252, then Latin-1. Unencoded
  `file://` URLs (with spaces) resolve, and `http(s)://` stream entries
  are skipped instead of becoming bogus local paths.

- **Malformed CUE/skin files can no longer crash the app.** Huge minute
  values in `INDEX` timecodes and hostile `NumPoints` in a skin's
  `region.txt` hit integer-overflow traps; both now fail soft. CUE
  parse errors also report correct line numbers in CRLF files and point
  at the offending TRACK line.

- **Damaged or oversized skin archives load instead of failing.** One
  corrupt entry (bad CRC) aborted the whole `.wsz`; now it's skipped.
  Decompression is capped (32 MB/entry, 96 MB total) against zip bombs,
  and partially out-of-bounds sprites fall back to built-in drawing
  instead of stretching garbage.

- **Space works in the playlist search and Jump-to-File fields.** The
  Play/Pause menu item claimed bare Space as its key equivalent, which
  AppKit matches before text fields see the key — toggling playback
  mid-typing. Space still toggles playback when no text field is active.

- **Gapless CUE playback bookkeeping.** Seeking within a cue track left
  a stale queued segment record, derailing auto-advance (tracks were
  skipped while the wrong title showed); the elapsed-time display
  overcounted by a full track after every gapless transition; pausing,
  seeking, then resuming played past the cue track's end to EOF; and
  repeat-one on a cue track replayed the entire album file from 0:00.

- **EQ preamp survives volume and mute changes.** Volume/mute writes to
  the mixer dropped the preamp factor until the preamp slider was
  touched again.

- **Playlist edits while playing stay coherent.** Removing the playing
  track now hands playback to the track that slid into its slot (or
  stops at the end of the list) instead of leaving audio playing a
  removed file with the wrong row highlighted and a track skipped on
  advance. Clearing the playlist stops playback. Shuffle follows the
  exact playing entry (not the first duplicate of the same file), and a
  FLAC+cue inside a mixed batch no longer jumps ahead of files listed
  before it.

- **CUE sheets with absolute Windows/Unix `FILE` paths resolve** by
  falling back to the basename next to the `.cue`, matching
  Winamp/foobar2000 behavior.

- **Right-click in a filtered playlist targets the clicked row.** The
  context menu indexed the unfiltered model, so with an active search
  it acted on a different track. Jump-to-File likewise re-resolves its
  selection against the live playlist, so reordering/deleting tracks
  while the panel is open can't play the wrong entry.

- **Opening "Import from Music Library…" twice no longer wedges the
  sheet permanently;** the View-menu checkmarks for Show Equalizer /
  Show Playlist now track the actual panel state; the skinned playlist
  footer count/duration refreshes when tracks change.

- **Small fixes:** unskinned time display clamps at 99 minutes instead
  of dropping the leading digit past 100; double-click reset-to-center
  applies only to balance/EQ sliders (not seek/volume); the spectrum
  analyzer works after session restore and guards against tiny FFT
  buffers; `viscolor.txt` files with leading comments no longer shift
  the palette.

- **Recalibrate playlist mini-transport hit-rects to Webamp's 10×10
  spec.** The first wire-up used 22×18 rects which overlapped each
  other (clicking visible PLAY fired PREV, etc.) and missed the
  leftmost ~2 px of PREV outright. Rects now match
  `.playlist-action-buttons` from `webamp/css/playlist-window.css`
  verbatim — clicks land on the button under the cursor, including
  the previously-dead edges.



- **CUE sheets with CRLF line endings now parse correctly.** EAC and
  other Windows tools write CUEs with `\r\n` terminators. Swift treats
  `\r\n` as a single extended grapheme cluster, so a Character-level
  newline split never matched and the entire file collapsed into one
  "line", triggering `noTracks`. The parser now splits on Unicode
  scalars instead, so each `\r` and `\n` is treated independently.

- **Dropping a `.cue` (or `.m3u`/`.m3u8`) onto playlist rows now works.**
  The table view's drop handler routed external files through
  `PlaylistManager.addURLs` directly, which filters by
  `Track.supportedExtensions` (audio only) and silently dropped cue and
  m3u files. Drops on the empty area of the playlist already worked
  because they went through `AppDelegate.handleOpenURLs`. Both paths
  now share that single routing entry point, so cue sheets and m3u
  playlists are accepted regardless of where on the playlist the user
  releases them.

- **Skinned playlist's bottom mini-transport area no longer covers skin
  artwork.** The 97×13 rectangle painted over the mini-player buttons
  baked into pledit.bmp's bottom-right corner sprite has been removed.
  Any solid fill — black or pledit `Normal=` — clipped surrounding skin
  artwork on many skins, leaving a visible patch below the running-time
  LCD. The mini buttons are now shown as the artist drew them; they
  remain non-interactive (main-window transport is still the single
  source of truth), but the strip blends correctly with every skin.
  Unskinned mode is unchanged.

- **Skinned playlist now uses the skin's `pledit.txt` colors.** The row
  background and selection highlight were hardcoded to black and Wamp's
  built-in blue, hiding the `normalbg` and `selectedbg` values from the
  loaded skin. `WinampRowView` now reads `WinampTheme.provider.playlistStyle`
  when a skin is active, so Bento-style brown rows and skin-defined
  selection colors render correctly. Unskinned mode is unchanged.

### Changed

- **Multi-select in the playlist.** Standard macOS selection now works:
  Shift-click extends a contiguous range, Cmd-click toggles individual
  rows, and Cmd+A selects every track. Backspace removes the entire
  selection at once. Double-click-to-play is unaffected.

- **Angular playlist scroller in unskinned mode.** The native AppKit
  `.legacy` scrollbar's rounded corners clashed with the rest of Wamp's
  pixel-perfect chrome. A custom `AngularLegacyScroller` now draws a flat
  rectangular knob with a 1-px chiseled border using the existing button
  palette, so the scrollbar matches the frame. Skinned mode is unchanged —
  the sprite-based `PlaylistSkinScroller` overlay still draws on top.

- **Default Always-on-Top is now OFF for fresh installs.** Previous default
  pinned the player above other apps on first launch, which most users find
  intrusive. Existing users keep their last-session choice — only the
  initial default changed.

- **SF Symbol icons in the menu bar and corner popup.** Every menu item now
  carries a contextual SF Symbol — `playpause.fill` next to Play/Pause,
  `magnifyingglass` next to Jump to File, and so on. Faster visual scanning,
  consistent with macOS native apps.

- **Title-bar corner menu mirrors the menu bar.** The popup that appears when
  you click the top-left corner of the player is now built from the same
  factory as the menu bar, so it always carries the full action set —
  including Jump to File…, Import from Music Library…, and Select All.
  Previously the two menus were hand-rolled separately and drifted apart.

### Added

- **Import from Music Library** — new File → Import from Music Library…
  menu item opens a sheet listing "All Songs" plus your user and smart
  playlists from Music.app. Check the sources to import, pick "New
  playlist" or "Append to current", and Wamp pulls in every local track
  it can see. Streaming-only tracks (not downloaded) and entries whose
  files have been removed are skipped with counts in the summary
  alert. Backed by the `iTunesLibrary` framework; falls back to parsing
  `~/Music/iTunes/iTunes Music Library.xml` if it's been enabled. First
  use triggers the macOS permission prompt; a denied state offers a
  direct link to Privacy & Security → Media & Apple Music.

- **M3U / M3U8 playlists** — drop a `.m3u` or `.m3u8` on the player, open
  one via File → Open, or double-click from Finder to import its tracks.
  Present files are appended to the current playlist; missing entries are
  counted and surfaced in a summary alert so dead references don't silently
  disappear. Parser handles `#EXTM3U` / `#EXTINF` metadata, mixed
  CRLF/LF/CR line endings, UTF-8 BOM, and the Latin-1-vs-UTF-8 extension
  convention (`.m3u` → Latin-1, `.m3u8` → UTF-8).

- **Non-goals documented** — `docs/non-goals.md` explains why Wamp does
  not (and will not) stream Spotify or Apple Music catalog tracks: both
  route audio through a system-managed graph that bypasses our DSP, so
  EQ and spectrum wouldn't apply.

- **CUE sheet support** — drop a `.cue` on the player, or open a FLAC with an
  embedded `CUESHEET` Vorbis comment, to split one long audio file into
  individual virtual tracks in the playlist. External `.cue` next to a FLAC
  wins over an embedded CUESHEET. Playback transitions between consecutive
  cue tracks on the same file are gapless via chained `scheduleSegment` calls.
  Encoding detection handles UTF-8, Shift-JIS, CP-1251, and CP-1252 cues.
  Right-click a cue track → "Reveal Source File in Finder".
  ([feat/cue-sheets](docs/superpowers/plans/2026-04-17-cue-sheets.md))
- **Jump to file** — Cmd+J or Ctrl+J opens an incremental search dialog over
  the current playlist. Matches are ranked by prefix → word boundary →
  substring, with the currently-playing track pre-selected on open. Enter
  plays the selection, Esc closes. Targets <16ms response on 10k-track
  playlists. ([feat/jump-to-file](docs/superpowers/plans/2026-04-17-jump-to-file.md))
