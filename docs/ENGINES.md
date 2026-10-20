# Local engines, downloads and licenses

[English README](../README.md) · [Русская инструкция](../README.ru.md)

CitrusDrop's own source is licensed under [MIT](../LICENSE). Optional external engines retain their respective licenses. They are downloaded from their publishers when requested, rather than included in CitrusDrop's app ZIP or source repository. No subscription or paid conversion API is involved.

## What runs where

| Work | Engine | Network during conversion |
|---|---|---|
| Images, PDF, simple text, subtitles, archives | macOS frameworks/tools and CitrusDrop code | None |
| Video, audio, WebP and AVIF | FFmpeg / FFprobe | No cloud upload; local processing |
| Documents, spreadsheets, presentations | LibreOffice | No cloud conversion; local processing |

Engine setup downloads binaries over HTTPS. There is no automatic update loop. After setup, local-file conversions work offline; operating-system trust checks are controlled by macOS. System/Homebrew engines can also be used if installed. No installation rewrites or removes those existing engines.

Managed locations:

```text
~/Library/Application Support/CitrusDrop/Engines/
├── ffmpeg-9.0.2/
│   ├── ffmpeg
│   └── ffprobe
└── LibreOffice-26.8.1.app/
```

`CITRUSDROP_ENGINES_DIR` overrides this directory for isolated tests. The command-line entry point is `CitrusDrop --install-engines`; it installs missing media/Office support. The app also exposes setup through Dependencies.

## FFmpeg 9.0.2

[FFmpeg's official download page](https://www.ffmpeg.org/download.html) supplies source and links external binary providers. CitrusDrop uses **Martin Riedl's independently published static builds** for both architectures, not binaries claimed to be produced by the FFmpeg project.

- Publisher/build script: [build server](https://ffmpeg.martin-riedl.de/), [source build script](https://git.martin-riedl.de/ffmpeg/build-script).
- Signature: **Developer ID Application: Martin Riedl**, Apple team **`KU3N25YGLU`**.
- License: **GPL version 3 or later** for these configured builds. The build enables `--enable-gpl` and `--enable-version3`, without `--enable-nonfree`. See [FFmpeg legal information](https://www.ffmpeg.org/legal.html), [GPLv3](https://www.gnu.org/licenses/gpl-3.0.html), and the exact [arm64](https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931890_9.0.2/versions.txt) / [Intel](https://ffmpeg.martin-riedl.de/download/macos/amd64/1789931006_9.0.2/versions.txt) configurations and dependency versions.
- Source: [FFmpeg 9.0.2 source archive](https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz). Codec dependency sources are linked by the build publisher; their own licenses also apply.
- Actual downloaded binaries were inspected: minimum macOS **12.0**, native arm64/x86_64, only Apple system dynamic-library dependencies, original vendor signatures verified. No Rosetta is needed for the native matching architecture.

| Architecture | Pinned archive | SHA-256 of archive |
|---|---|---|
| Apple silicon | [ffmpeg.zip](https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931890_9.0.2/ffmpeg.zip) | `c8ed4c4e6978a03c485edbfe4e0a5dc2380f8a30bba5150531b31b094492d924` |
| Apple silicon | [ffprobe.zip](https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931890_9.0.2/ffprobe.zip) | `fcbe839537485eaee7a7a8bc5cbc0f90d53617e80943e8a5b2e31cb851197ea6` |
| Intel | [ffmpeg.zip](https://ffmpeg.martin-riedl.de/download/macos/amd64/1789931006_9.0.2/ffmpeg.zip) | `7c6b4125b191cbf773832dc51f424cf2b6bb7da43007d1e066f95909e47cacd4` |
| Intel | [ffprobe.zip](https://ffmpeg.martin-riedl.de/download/macos/amd64/1789931006_9.0.2/ffprobe.zip) | `2322438ed2f6319a691291b247d09c69dcaa3a982460d1f269a7e1af335cfdfd` |

Each publisher checksum is available by appending `.sha256` to the ZIP URL. Media downloads total about 57 MB on Apple silicon / 68 MB on Intel; installed executables occupy about 132 MB / 189 MB in decimal units.

## LibreOffice 26.8.1

- Publisher: [The Document Foundation / official LibreOffice downloads](https://www.libreoffice.org/download/).
- Signature: **Developer ID Application: The Document Foundation**, Apple team **`7P5S3ZLCN7`**.
- License: **Mozilla Public License 2.0**, with third-party components under additional licenses. [Official license page](https://www.libreoffice.org/licenses/). The intact app bundle contains its version-specific license notices; these are preserved.
- Source: [official 26.8.1 source listing](https://download.documentfoundation.org/libreoffice/src/26.8.1/).
- Requirements: [macOS 11 or later, Intel or Apple silicon](https://www.libreoffice.org/system-requirements/). The downloaded arm64 app was verified as build **26.8.1.1**, minimum macOS **11.0**. Intel's download metadata and checksum were verified; physical Intel execution has not been tested here.

| Architecture | Official pinned DMG | SHA-256 of DMG |
|---|---|---|
| Apple silicon | [LibreOffice_26.8.1_MacOS_aarch64.dmg](https://download.documentfoundation.org/libreoffice/stable/26.8.1/mac/aarch64/LibreOffice_26.8.1_MacOS_aarch64.dmg) | `ca074e0b13571efb30a31fc531c5f95e997030637325e5d5de92d67aefdf0dfc` |
| Intel | [LibreOffice_26.8.1_MacOS_x86-64.dmg](https://download.documentfoundation.org/libreoffice/stable/26.8.1/mac/x86_64/LibreOffice_26.8.1_MacOS_x86-64.dmg) | `4c7464313a529e9074400cbcdc894fc40ac4ef9421ded03b16b5a78d12cb155e` |

Official checksums and mirror metadata are available by appending `.sha256` or `.metalink` to each DMG URL. Official download URLs may redirect to a Document Foundation mirror; the installer requires HTTPS throughout and checks the pinned hash. DMGs are about 299 MB arm64 / 309 MB Intel.

## Installation validation

Setup checks SHA-256 before unpacking, validates the expected media archive filenames, and verifies the original Apple Developer ID signatures against the publisher team IDs above. LibreOffice's disk image is mounted read-only and the complete app is copied into staging. Both engines must report the expected version before the final directory is moved into place.

Setup does not replace unexpected existing destinations, remove quarantine attributes, re-sign vendor binaries, require `sudo`, or disable Gatekeeper. Cancelled setup cleans its temporary stage; an already completed engine installation remains available. LibreOffice conversions use isolated temporary profiles and disable macros/active content in those profiles.

The CitrusDrop release itself currently has an ad hoc signature. A valid signature confirms code integrity but is not Apple notarization. Initial macOS approval may still be required. Use [Apple's normal opening flow](https://support.apple.com/en-us/102445); organization-managed restrictions may require an administrator-approved build.

The published app targets macOS 13+. Native engine inspection supports this target, but does not replace hardware testing on every macOS release or every Mac. Available codec combinations, source-file quality, document fonts and Office layout can still affect results.
