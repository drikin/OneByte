# OneByte

**For those of us who type in 2-byte languages but think in QWERTY.**

Every Japanese typist knows the pain: switch to Kotoeri (or Google Japanese Input), type romaji, hit space a dozen times cycling through kanji candidates, realize the segmentation was wrong, backspace, re-segment, repeat. Then you switch back to English mode for that one URL, and forget to switch back. We've all been there.

OneByte throws that 50-year-old IME paradigm out the window.

**Type romaji. Press Enter. Get clean Japanese.** Typos? Missing letters? Wrong segmentation? Doesn't matter. The LLM fixes everything in one shot. No candidate window. No mode switching. No spacebar mashing.

Need English instead? **Shift+Enter.** Done.

Built on Swift + InputMethodKit, backed by a local LLM (vLLM on a DGX Spark cluster via Tailscale).

## How It Works

```
watashi wa kyou gakkou ni ikimashita
         ↓ Enter
私は今日学校に行きました。
```

```
koreha tesuto desu
         ↓ Shift+Enter
This is a test.
```

**No IME mode switching. No kana-kanji conversion candidates. No spacebar cycling.** Just type romaji, press Enter, and the LLM handles everything — segmentation, kanji choice, typo correction, and natural phrasing.

## Key Bindings

| Key | Action |
|---|---|
| Type romaji | Accumulates in marked text (underline) |
| **Space** | Phrase separator |
| **Enter** | Convert everything to Japanese |
| **Shift+Enter** | Convert to Japanese → translate to English |
| **Tab** | Commit as-is (raw romaji, no LLM) |
| **Backspace** | Remove last character / pop phrase |
| **Escape** | Clear buffer |
| **Cmd+anything** | Pass through (copy, paste, select all, etc.) |

## Requirements

- macOS 15+ (Sequoia) — Apple Silicon (arm64)
- A running vLLM instance (default: `100.78.215.127:8000` with model `spark-local`)
- Tailscale connectivity to the LLM server (or adjust `inferenceURL` in the source)

## Installation

### Quick install (from gist)
```bash
bash <(curl -sL https://gist.githubusercontent.com/drikin/5136e194cf6e74695193317363e409af/raw/build-and-install.sh)
sudo cp -r /tmp/OneByte_Build/OneByte.app /Library/Input\ Methods/
sudo chmod -R 755 /Library/Input\ Methods/OneByte.app
sudo xattr -cr "/Library/Input Methods/OneByte.app"
```

Then: **System Settings > Keyboard > Input Sources > Add "OneByte"**

### Build from source
```bash
git clone https://github.com/drikin/OneByte.git
cd OneByte
bash build-and-install.sh
sudo cp -r /tmp/OneByte_Build/OneByte.app /Library/Input\ Methods/
sudo chmod -R 755 /Library/Input\ Methods/OneByte.app
sudo xattr -cr "/Library/Input Methods/OneByte.app"
```

## Architecture

OneByte uses `handleEvent:client:` to capture all key events (Apple's recommended pattern for InputMethodKit). `Cmd+` keys are passed through immediately. All other keys are processed on `@MainActor` via `DispatchQueue.main.sync`. Conversion is done asynchronously via Swift Concurrency (`Task`) with a 3-second timeout and romaji fallback on error.

```
handleEvent → handleOnMain → [buffer chars]
                           → [Enter] → Task { LLM POST } → insertText
                           → [Tab]   → insertText(romaji)
```

### Key design decisions
- **Left/Right Cmd detection**: Rejected — `NSEvent.ModifierFlags.rightCommand` is not a real API. Use `Shift+Enter` instead.
- **Phrase array** (`phrases:[String] + current:String`): Space separates phrases. LLM receives the full concatenated text for context-aware conversion.
- **No on-device fallback**: If the LLM is unreachable, the romaji text is inserted as-is. A local conversion engine (Mozc-based) is a future consideration.

## Configuring the LLM endpoint

The endpoint URL is hardcoded in `OneByteInputController.swift`. To change it:

```swift
private let inferenceURL = URL(string: "http://YOUR_SERVER:PORT/v1/chat/completions")!
```

Future versions will externalize this to `UserDefaults` or a config file.

## License

MIT
