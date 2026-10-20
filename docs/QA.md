# CitrusDrop 0.2.0 — verification

21 October 2026. Local runtime: Apple silicon, macOS, Swift 6.1.2 / Apple Command Line Tools. These results describe tested fixtures, not every possible source file or codec.

## Real conversion checks

- **41 core checks passed**, using only the managed FFmpeg 9.0.2 and LibreOffice 26.8.1 engines, with discovery of system/Homebrew engines disabled. See [exact output](test-results.txt).
- **42 final managed-engine checks passed**: PNG/JPEG/HEIC/TIFF/BMP/GIF/WebP/AVIF/PDF outputs decoded at the expected dimensions, all eight audio formats decoded, MP4/WebM with sound, actual compression and unchanged originals. See [image and managed-media report](image-test-results.json).
- **56 media checks passed** against FFmpeg 9.0.1: all offered audio/video targets, real decoding, odd dimensions, phone rotation, silent video, trim timing, metadata, alpha, surround sound and HDR. See [media report](media-test-results.json).
- **142 Office conversion paths / 376 assertions passed** with real Word, Calc and Impress files, Cyrillic, tables, pictures, legacy formats, UTF-8 CSV/TSV, EPUB export and every-page image output. See [Office report](office-test-results.json).
- **82 integrated Office assertions passed** through the application's Converter, including original preservation, collisions, cancellation and staging. See [integration report](office-integration-results.json).
- **8 final managed Office checks passed**, including fresh-engine publisher signatures before/after conversion, a parent environment without the bytecode override, and no external HTML-image requests. See [managed Office report](managed-office-results.json).

Core checks cover native image tools and compression, text-preserving PDF compression, PDF pages/merge/split, subtitle round trips, archives, traversal/link rejection, shell metacharacters in paths, batching, no overwrites and cancellation. Unsupported document tools are rejected, and a canceled image-only PDF merge produces no result.

Office subprocesses run with IP networking denied while retaining local Unix IPC. An actual localhost HTML-image server received zero requests; normal DOCX, PDF and XLSX conversion still succeeded. Embedded Python bytecode writes are disabled so ordinary conversions retain the vendor signature; a fresh managed installation passed strict deep signature verification after the version probe and conversions. HTML with remote resource references is rejected explicitly as well. Macro execution is disabled in fresh per-conversion Office profiles.

## Engine setup and installer

A cold installation into an isolated managed-engine folder downloaded FFmpeg/FFprobe and LibreOffice from pinned HTTPS vendor URLs, checked SHA-256, architecture, vendor signatures and execution, then ran real conversions. Existing managed engines were reused; unexpected destination contents were preserved. No Homebrew or administrator privileges were used.

The application installer was exercised with isolated GitHub-style fixtures: fresh install, canonical and dist-prefixed manifests, backup preservation, running-app refusal, checksum mismatch and failure cleanup. Public-release download verification is recorded separately after publication.

## Build scope

The release app is compiled separately for arm64 and x86_64, combined with lipo and checked with codesign --verify --deep --strict. It uses an ad hoc signature; Apple Developer ID notarization is unavailable. The deployment target is macOS 13. Apple silicon was run-tested; a physical Intel Mac and macOS 13 machine were not available.

The public Actions workflow performs real conversion checks before universal packaging. Hosted workflow status is distinct from local test evidence; a prepared workflow alone is not a successful hosted run.

## Interface and Finder

Russian and English windows, persisted language choice and the radial menu were inspected in the running app. Real Finder Services entries were used to open the wheel and convert PNG to JPEG, and to compress a JPEG into a smaller output. The operating system's folder and Finder Automation permissions were granted by the user. Screenshots in [screenshots/](screenshots/) show the actual native app.

The CUA input API cannot send a modifier by itself or retain Shift during a drag. Therefore physical Shift-tap and Shift-drag are implemented and reviewed but are not marked as automated end-to-end checks. Finder Services and conversion are independently verified.

## Final mode-switching regression check

The actual final universal app was operated through its native UI. Convert, Tools and Actions show distinct headings, icons and operation labels even with no file selected. A controlled PNG was converted to a decoded 320×180 JPEG; Rotate produced a 180×320 PNG; Duplicate created a byte-identical copy and visible success/reveal controls. The original SHA-256 was unchanged. JPG and Rotate choices survived language changes and switching between modes. Both languages were visually inspected.
