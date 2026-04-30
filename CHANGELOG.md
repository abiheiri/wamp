# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed

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
