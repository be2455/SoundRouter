# Contributing

*English · [繁體中文](CONTRIBUTING.zh-TW.md)*

## Read this first: a silent app is usually a permissions problem

Core Audio process taps require the system audio-capture permission. **Without it, `AudioHardwareCreateProcessTap` still succeeds, the IOProc still runs at full rate, the buffer layout is still correct — and every sample is zero.** Nothing reports an error anywhere.

So the first time you build and route an app and hear nothing, it is almost certainly not a bug you introduced. Check this before anything else:

1. Build with `./Packaging/build-app.sh` and launch `build/SoundRouter.app`.
2. Change any app's output device. macOS should prompt for permission — allow it.
3. If no prompt appears, look in System Settings → Privacy & Security → Screen & System Audio Recording.

Builds are **ad-hoc signed**, so the signature hash changes on every rebuild and macOS may treat each build as a new app that needs the permission again. To stop that:

1. Keychain Access → Certificate Assistant → Create a Certificate…
2. Name it anything, Identity Type "Self Signed Root", Certificate Type "Code Signing".
3. Build with `CODESIGN_IDENTITY="Your Certificate Name" ./Packaging/build-app.sh`.

## Getting set up

```bash
git clone https://github.com/dws741119/SoundRouter.git
cd SoundRouter
swift build          # library, CLI and app
swift test           # hardware-independent logic only
./Packaging/build-app.sh
```

Requires macOS 15+ and Swift 6. No external dependencies — it builds offline.

## Debugging

The CLI is the fastest way to see what the audio layer is actually doing. Because it needs bundle identity for the permission, run the bundled copy:

```bash
open -n -a "$PWD/build/AudioRouterProbe.app" --args \
  --log /tmp/probe.log route Spotify --to "Speakers" --meter --debug --seconds 10
cat /tmp/probe.log
```

`--debug` prints the tap format, the aggregate device's buffer layout, IOProc call counts and the raw pre-gain peak from the tap. That last number is the one that separates "the tap is giving us silence" from "we are computing the wrong thing".

`--keep-original` taps without muting the source app, so you can measure a tap while still listening normally.

The menu bar app has no stdout, so it overwrites `~/Library/Logs/SoundRouter-status.txt` on every refresh with the devices and playback sources it can see. When the UI looks wrong, read that first — it tells you immediately whether the problem is the data or the layout.

## Before you touch the render path

`RouteEngine.render` runs on a real-time audio thread. Inside it:

- no memory allocation
- no locks
- no Objective-C or Swift runtime calls that might allocate (no `String`, no arrays, no closures that escape)

Parameters that the UI can change while audio is running (volume, mute, balance) live in a single block of memory allocated once, written from the main thread and read from the audio thread. That is deliberate. If you need to add a parameter, put it in that struct rather than reaching for a lock.

## Tests

`swift test` covers only logic that needs no audio hardware — mainly the rules that group helper and XPC processes back into their owning app. That grouping decides whether routing an app captures anything at all, so it is worth guarding.

Taps and aggregate devices are deliberately **not** tested. They need real devices and a granted permission; running them in CI would only produce a false green. If you add tests, prefer this split: extract the pure decision, test that, and leave the Core Audio call at the edge.

CI runs `swift build` and `swift test` on a macOS runner. It cannot verify any actual audio behaviour.

## Code style

Match the surrounding code. A few conventions that matter here:

- **Comments explain why, not what.** This codebase talks to an API with several behaviours that are not documented and not guessable — an unauthorized tap being silent, the HAL never notifying `kAudioProcessPropertyIsRunningOutput`, `ScrollView` having no intrinsic height inside `MenuBarExtra`. Where you discover something like that, write it down next to the code that depends on it. Those comments are the most valuable part of this repository.
- **Always name the type when reading a Core Audio property**: `try obj.read(selector, as: UInt32.self)`. Without the explicit type, `try?` can infer the generic as `Optional<UInt32>`, which computes a size one byte too large, gets rejected by Core Audio, and is then swallowed into `nil`. `read` asserts against this in debug builds.
- Existing comments are in Traditional Chinese. English is fine for new code; the mix is acceptable for now and translation is welcome.

## Pull requests

- Say what you tested and on what hardware. "Tested routing Spotify to a USB DAC on macOS 26, Apple Silicon" is far more useful than "works".
- Audio bugs are often hardware-specific. Sample rate, channel count and interleaving of your device all matter — include them when reporting one.
- Keep unrelated changes out of the diff.

## Known gaps, if you are looking for something to do

- EQ / AudioUnit effect chains — the hook point is in `RouteEngine.render`, just before writing the output buffer.
- Splitting one app across several output devices.
- AirPlay: targets appear as Core Audio devices, but whether one can serve as an aggregate sub-device is untested.
- Intel Macs have not been verified at all.
