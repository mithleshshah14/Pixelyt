# Pixelyt — Implementation Notes

This document summarizes what's been built so far: the core metadata-cleaning
app, the Android system-picker integration, and the Tools/Resize/Albums
additions.

## Core concept

Pixelyt strips hidden metadata from photos (GPS location, camera
make/model/serial, software tags, thumbnails, artist name, etc.) while
deliberately keeping the one thing worth keeping: **when the photo was
taken**. Metadata is never touched silently — the user always sees what a
photo carries before choosing to clean it.

## App structure

- `lib/main.dart` — entry point. `_LaunchRouter` decides at startup (and on
  every subsequent intent while the app is already running) whether Pixelyt
  was opened normally or because another app asked the system to let the
  user pick a photo, and routes to `RootScreen` or `PickerScreen`
  accordingly.
- `lib/screens/root_screen.dart` — the normal launch entry point: a
  bottom-navigation shell (`NavigationBar`) with two tabs, **Clean** and
  **Tools**, each keeping its own state via `IndexedStack`.

## Clean tab (`lib/screens/home_screen.dart`)

- **Home/idle state** shows two "album" cover cards (see Albums below)
  instead of a blank screen, plus **Choose photo** / **Camera** buttons.
- **Choose photo** opens the system photo picker (`image_picker`,
  multi-select via `pickMultiImage()`), so multiple photos can be picked at
  once.
- Picking multiple photos puts you in a **swipeable review** (`PageView`):
  swipe left/right between them, with a slideshow-style dot indicator and
  an app-bar counter (`Pixelyt (2/5)`). Each photo has fully independent
  state — reviewing, cleaning, or already-cleaned — so cleaning one doesn't
  disturb the others, and you can swipe back to review an already-cleaned
  photo without losing its result.
- As soon as a photo is picked, it's shown **immediately** with a "Fetching
  metadata…" overlay while `MetadataStripper.preview()` runs in a
  background isolate (`compute()`), so the UI never blocks on the decode.
  The rest of a multi-select batch is **prefetched in the background** (one
  at a time) after the first photo loads, so swiping to the next photo
  usually finds it already ready.
- The review card shows: how many metadata fields the photo carries, the
  capture date/time (which will be kept), and whether it includes GPS
  location — **only when a real latitude/longitude exists**, not just
  because a GPS block is present (some cameras write a `GPSVersionID` stub
  with no location fix; this used to false-positive).
- **"Show metadata"** opens a bottom sheet listing every raw EXIF field
  found (name + value), not just the curated highlights.
- **"Clean & save"** prompts for a filename (pre-filled with
  `<original name>_clean`, editable), then:
  1. strips metadata (`MetadataStripper.strip()`, off the UI thread),
  2. writes the result to disk,
  3. saves it to the system gallery automatically (`Gal.putImage`) — no
     separate manual save step needed,
  4. adds it to the **"Cleaned photos"** album/history.
- The system back gesture, while reviewing/cleaning, returns to the app's
  home view instead of exiting the app (`PopScope`).

### Metadata service (`lib/services/metadata_stripper.dart`)

- `preview(bytes)` — reads what metadata exists without modifying anything:
  curated highlights (camera make/model, software, artist, copyright, GPS),
  capture date, and a total field count.
- `readAllFields(bytes)` — every raw EXIF tag (name + value) found, across
  all IFDs (main, Exif sub-IFD, GPS sub-IFD).
- `strip(bytes)` — builds a **brand-new** EXIF block (nothing copied over)
  containing only `DateTime`/`DateTimeOriginal`, bakes EXIF orientation into
  the pixels first (since the tag itself is about to disappear), and
  re-encodes. GPS presence is judged by an actual lat/long pair, not just a
  non-empty GPS block.

## Android picker integration

Pixelyt can appear as a source in *other apps'* "choose a photo" flows
(e.g. an upload button in WhatsApp/Instagram/etc.), so a photo can be
cleaned on the way out without a separate app-switch.

- `AndroidManifest.xml` registers `MainActivity` for
  `ACTION_GET_CONTENT`/`ACTION_PICK` with `image/*`, alongside the normal
  launcher intent-filter.
- `lib/services/picker_channel.dart` — Dart↔native bridge
  (`removetrack/picker` MethodChannel). Exposes the launch action and a
  stream for it, since Android delivers a **new** picker request to an
  **already-running** Pixelyt via `onNewIntent`, not a fresh launch — the
  stream is what makes the app notice that and switch into picker mode
  instead of getting stuck showing whatever screen was already up.
- `android/.../MainActivity.kt` — forwards `onNewIntent`'s action to Dart,
  and exposes `returnPickedImage(path)` (wraps the cleaned file in a
  `FileProvider` URI, sets it as the activity result, finishes) and
  `cancelPicker()`.
- `lib/screens/picker_screen.dart` — the picker-mode UI: an in-app gallery
  grid (`lib/widgets/gallery_grid.dart`, via `photo_manager`, since it
  resolves real filenames unlike the system picker's redacted URIs — see
  note below). Tapping a photo cleans it and immediately hands the result
  back to the calling app; no metadata-review step here, since the whole
  point of this flow is a fast pass-through while uploading elsewhere.

**Known trade-off:** the normal Clean tab uses the *system* photo picker
(by request, reverted from an earlier in-app-grid version), and Android's
modern Photo Picker deliberately returns privacy-redacted content URIs to
apps without full photo-library permission — their `DISPLAY_NAME` can be
just a numeric picker ID (e.g. `47`) instead of the original filename. This
is an Android platform behavior, not a bug in Pixelyt.

## Tools tab

- `lib/screens/tools_screen.dart` — a list of available tools; currently
  just **Resize image**.
- `lib/screens/resize_screen.dart` — pick a photo (auto-prompts on open),
  then:
  - set exact **width/height in pixels**, with an aspect-ratio lock toggle
    (editing one field auto-computes the other; toggle off to stretch to
    an arbitrary size),
  - optionally set a **target file size** (KB or MB) — independent of the
    dimensions,
  - **Resize** produces the result off the UI thread
    (`lib/services/image_resizer.dart`): resizes to the exact dimensions,
    then if a size cap was given, steps JPEG quality down until the output
    fits (re-encoding as JPEG even for a PNG source, since PNG has no
    quality knob to shrink with).
  - Save prompts for a filename (default `<name>_<width>x<height>`), saves
    to the gallery, and adds it to the **"Resized photos"** album.

## Albums (history)

- `lib/services/output_history_service.dart` — a small durable history,
  one per category (`cleaned` / `resized`): copies each output into an app
  documents subfolder plus a JSON manifest, capped at 30 entries per
  category with automatic pruning (oldest deleted first, files included).
  Survives app restarts.
- `lib/widgets/album_section.dart` (`AlbumCard`) — a big cover-photo card
  (16:9, rounded corners, bottom gradient with title + photo count) shown
  on the Clean tab's home view — one for **Cleaned photos**, one for
  **Resized photos**. Empty state shows a placeholder icon + hint instead
  of nothing.
- `lib/screens/album_detail_screen.dart` — tapping a card opens a 3-column
  grid of every photo in that album.
- `lib/screens/photo_preview_screen.dart` — tapping a grid photo opens a
  full-screen, pinch-to-zoom (`InteractiveViewer`) preview with a share
  button.

## App icon

- Generated via `flutter_launcher_icons` from `Pixelyt.png`, with a proper
  **adaptive icon** (explicit foreground + background layers). Without
  this, Android auto-shrinks a legacy (non-adaptive) icon to fit inside its
  own default safe-zone inset, which is why the icon looked smaller than
  expected before this was added.

## Shared utilities

- `lib/services/file_helper.dart` — writes output bytes to a scratch file
  in the app's cache dir (used for the picker hand-off and as a staging
  file before `Gal.putImage`/`Share`), plus filename sanitizing.
- `lib/widgets/save_name_dialog.dart` — the reusable "save as" filename
  prompt used by both the Clean and Resize flows.
