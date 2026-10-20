# CitrusDrop
<!-- impeccable:product-schema 1 -->
## Platform
Native macOS 13+, AppKit, Swift. Universal Apple silicon and Intel app.
## Users
Mac users converting local files while working in Finder and other apps.
## Product Purpose
A free, open-source local file converter with a drag-triggered radial menu, batch conversion, and file tools. Originals must be preserved.
## Stack
Implementation choice: AppKit and system frameworks; optional verified FFmpeg and LibreOffice downloads managed inside the app. No service or API credentials.
## Reference
Interaction reference: https://www.tangerineformac.com/ and its public 4-second audio conversion demo. Instagram reference could not be fetched. No proprietary source or assets used.
## Constraints
No payments, accounts, analytics or file uploads. Engine downloads require an explicit Install action; the optional command-line installer installs missing engines by default. Show only supported conversions. Never silently overwrite an output. Russian and English UI with a saved language selector, confirmed by the user. Finder context actions, tap Shift on Finder selection, drag Shift, and compression are requested. Dark, futuristic, tidy, minimal window design was explicitly requested.
