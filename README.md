# Clacky

A tiny macOS menu bar app that plays mechanical keyboard sounds while you type on the built-in keyboard.

## Download

**[Download the latest Clacky.dmg](https://github.com/yashasviyadav2027/clacky/releases/latest)** — free, macOS 13 Ventura or newer, Apple Silicon and Intel.

1. Open the DMG and drag **Clacky** into **Applications**.
2. Clacky isn't from the App Store or notarized by Apple, so macOS blocks the first launch. Open Terminal and run:
   ```bash
   xattr -cr /Applications/Clacky.app && open /Applications/Clacky.app
   ```
   Or try to open it once, then go to System Settings → Privacy & Security and click **Open Anyway**.
3. When asked, turn Clacky on under System Settings → Privacy & Security → **Input Monitoring**.
4. Type anything — you should hear it.

Clacky is free to use but not open source: see [LICENSE](LICENSE). Bug reports and ideas are welcome in [Issues](https://github.com/yashasviyadav2027/clacky/issues).

## Build & run

```bash
./build.sh
open build/Clacky.app
```

To share it, run `./package.sh` — it makes `dist/Clacky.dmg` (universal: Apple Silicon + Intel, macOS 13+) with step-by-step install instructions inside. It isn't notarized by Apple, so the first launch needs System Settings → Privacy & Security → **Open Anyway** (covered in the instructions).

On first launch macOS asks for **Input Monitoring** (System Settings → Privacy & Security → Input Monitoring). Enable Clacky; it starts working within a couple of seconds.

The app only reads key *codes* to choose a sound — nothing is logged or stored, and macOS hides keystrokes in password fields from it entirely.

> You only grant this once. `build.sh` signs every build with the same self-signed identity, kept in a project-local keychain (`.signing/`, created by `scripts/setup-signing.sh` on first build — your login keychain is not touched), so macOS recognizes new builds as the same app. Don't delete `.signing/`, or you'll need to grant permission again.

**Using it:** click the menu bar icon for everything in one place — sound on/off, volume, ⭐ Favorites, Recently Used and all sounds (filter by Thocky / Creamy / Clacky / Clicky / Fun, hover ▶ to preview, click to use, ☆ to favorite). Right-click the icon for a quick favorites switcher (⌘1–⌘9). The gear opens Settings (General / Sounds / About).

Works with the built-in keyboard and any external USB or Bluetooth keyboard.

## Sounds

**Real switches** (default: Holy Panda) — recordings from [kbsim](https://github.com/tplai/kbsim) (MIT, © Thomas Lai), trimmed and loudness-matched, in `Resources/Packs/`:
Holy Panda, NovelKeys Cream, Alpaca, Gateron Black Ink, Gateron Red Ink, Turquoise Tealio, Topre,
Cherry MX Black / Blue / Brown, Kailh Box Navy, SKCM Blue Alps, IBM Buckling Spring.
Try them all in the browser at [kbs.im](https://kbs.im).

**Synthesized**: Thocky, Creamy, Clacky, Clicky.

**Fun**: Duck.

The switch next to the volume slider turns sound on/off.

Custom packs: menu → *Open Sound Packs Folder*, create a subfolder (its name shows up in the *Sound* menu) and drop audio files in it. The file name prefix decides when it plays:

| Prefix | Plays on |
| --- | --- |
| `space*` | space bar |
| `enter*` / `return*` | return, shift, caps lock |
| `backspace*` / `delete*` | delete |
| `up*` | any key release |
| anything else | normal key press |

Add several files per type (`down1.wav`, `down2.wav`, …) for natural variation.

A folder with the same name as a built-in sound replaces it — e.g. `Packs/Duck/` swaps the generated quack for your own recording. Personal recordings stay in that folder, outside the project and the app bundle.

To audition the built-in sounds as WAV files:

```bash
build/Clacky.app/Contents/MacOS/Clacky --export ~/Desktop/clacky-wavs
```
