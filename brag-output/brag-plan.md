# Spacewise — brag plan

**What it is:** a native macOS app that shows what is filling your disk and helps you clear it safely.
**For:** anyone whose Mac says the disk is almost full and has no idea why.
**What sets it apart:** a treemap of the whole disk in seconds, exact duplicates found by content, cleanup suggestions labelled Safe or Review, and everything removed goes to the Trash first. Native SwiftUI, no tracking.
**Most impressive claim (from the app's own copy):** scan your whole disk in seconds. The demo home folder scans "in under a second" on screen.
**Visual hook:** the app's own treemap (real `Treemap.layout` from Spacewise/Core, real category colours) slamming onto the screen block by block.
**Real UI shown:** Overview → click Home → scan result → Explore treemap → Duplicates → Cleanup list.
**Tone:** `default` — punchy, playful, clean. Dark mode to match the app.
**Share caption:** "Your Mac is full. Of what? Spacewise maps every byte in seconds, then clears caches, duplicates and old downloads — Trash first, nothing gone for good."

## Data and privacy
All screens are the real Debug build of Spacewise scanning a generated sample home folder ("alex", from `scripts/make-demo-data.sh`; files are random bytes). No real files, names or paths from the owner's Mac appear. The only real machine detail is the disk card (free space of "Macintosh HD"), which is not personal.

## Format
Landscape 1920×1080, 30 fps, 21.0 s (630 frames).

## Music
120 BPM (beat = 0.5 s, bar = 2 s), A minor, Am–F–C–G. Soft pluck + pad intro, kick from 1.0 s, full groove (clap on 2 and 4, offbeat hats, bass) from the reveal at 3.0 s. Every scene cut lands on a beat. Effects in key, mixed under the music: soft whooshes into each cut, a muted click on cursor clicks, a low "pop" under the icon. Final Am chord rings out from 20.0 s.

## Storyboard

| # | Time | Beats | Scene | On-screen text |
|---|---|---|---|---|
| 1 Hook | 0.0–3.0 | 0–6 | The real treemap of the sample home fills the frame, blocks popping in largest-first. Dimmed behind the text. | "Your Mac is full." (0.3 s) / "Of what?" (1.0 s), both held to 2.9 s |
| 2 Reveal | 3.0–5.5 | 6–11 | Blocks collapse into the centre; the app icon springs in, wordmark, subtitle. | **Spacewise** / "See and free up your storage." (App Store subtitle) |
| 3 Scan | 5.5–9.5 | 11–19 | Window rises in on Overview. Cursor glides to **Home**, clicks on the beat at 6.5 s; cut at 7.0 s to the scan result, push-in on "6.73 GB · 73 files · scanned in under a second". | "Scan your whole disk in seconds." |
| 4 Explore | 9.5–13.0 | 19–26 | Explore: treemap + sorted list, slow push-in on the treemap, cursor hovers a video block. | "Bigger blocks use more space." |
| 5 Duplicates | 13.0–15.5 | 26–31 | Duplicates: 3 copies of the same video, "Frees 650.1 MB" highlighted. | "Exact duplicates, found by content." |
| 6 Cleanup | 15.5–18.0 | 31–36 | Cleanup with Safe items ticked, list bar "Frees 1.95 GB"; cursor glides to **Move to Trash…** (no click). | "Labelled Safe or Review. Trash first." |
| 7 Outro | 18.0–21.0 | 36–42 | Icon, wordmark, line, link. | **Spacewise** / "Native for macOS. No tracking." / github.com/avinashchavan1/spacewise |

Transitions: window scenes swap content by stepping the old screen out (0.15 s scale-down and fade), then the new one in (0.2 s), never a straight crossfade. Captions slide up 24 px and fade in over 0.3 s, fade out over 0.2 s before the cut.
