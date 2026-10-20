---
name: CitrusDrop
description: Futuristic, tidy, minimal native macOS file utility
colors:
  window: "rgb(5.5% 7.1% 9.4%)"
  drop-surface: "rgb(7.5% 9.8% 13%)"
  wheel-sector: "rgb(10% 13% 17%)"
  secondary-button: "rgb(13% 16% 20%)"
  surface-line: "rgb(19% 24% 30%)"
  accent: "rgb(100% 62% 27%)"
  secondary-text: "rgb(69% 75% 82%)"
  footer-text: "rgb(57% 64% 72%)"
  selected-segment: "rgb(25% 34% 43%)"
  disabled-button: "rgb(15% 15% 15%)"
  primary-button-text: "rgb(6% 6% 6%)"
typography:
  title:
    fontFamily: "macOS system font"
    fontSize: "26pt"
    fontWeight: 600
  drop-heading:
    fontFamily: "macOS system font"
    fontSize: "18pt"
    fontWeight: 500
  body:
    fontFamily: "macOS system font"
    fontSize: "12pt"
    fontWeight: 400
  control:
    fontFamily: "macOS system font"
    fontSize: "13pt"
    fontWeight: 500
  primary-control:
    fontFamily: "macOS system font"
    fontSize: "13pt"
    fontWeight: 600
  wheel-format:
    fontFamily: "macOS system font"
    fontSize: "14pt"
    fontWeight: 600
  wheel-context:
    fontFamily: "macOS system font"
    fontSize: "12pt"
    fontWeight: 600
  wheel-count:
    fontFamily: "macOS system font"
    fontSize: "11pt"
    fontWeight: 400
  wheel-action:
    fontFamily: "macOS system font"
    fontSize: "10pt"
    fontWeight: 600
  footer:
    fontFamily: "macOS system font"
    fontSize: "10pt"
    fontWeight: 400
rounded:
  button: "9pt"
  drop-surface: "14pt"
spacing:
  outer-margin: "32pt"
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.primary-button-text}"
    typography: "{typography.primary-control}"
    rounded: "{rounded.button}"
  button-secondary:
    backgroundColor: "{colors.secondary-button}"
    typography: "{typography.control}"
    rounded: "{rounded.button}"
  button-disabled:
    backgroundColor: "{colors.disabled-button}"
    rounded: "{rounded.button}"
  drop-surface:
    backgroundColor: "{colors.drop-surface}"
    rounded: "{rounded.drop-surface}"
    width: "656pt"
    height: "180pt"
---

# Design System: CitrusDrop

## Overview

Native macOS file utility in Operate mode. The user pinned a futuristic, tidy, minimal appearance: graphite surfaces, a restrained orange accent, and compact system typography. Native interactions and clear local file operations take priority over ornament.

**Key Characteristics:**
- Graphite surfaces with orange reserved for the identity, primary action, and active drop targets.
- A fixed utility window and a compact radial menu share the same visual language.
- Russian and English UI with a saved, visible language selector.
- Native macOS controls, system colors, permission prompts, and accessibility semantics.

## Colors

### Primary

The custom warm orange `accent` marks the header symbol and enabled primary action. The wheel selection and file-drop hover use **AppKit `systemOrange`**, not the custom accent; retain that distinction.

### Neutral

The window, drop surface, wheel sectors, and secondary buttons form a restrained graphite hierarchy. `surface-line` outlines the drop surface; `selected-segment` tints the active native segment. Custom secondary and footer text colors establish the utility hierarchy.

Native content uses `labelColor`, `secondaryLabelColor`, and `disabledControlTextColor`. The primary button uses dark text, and an active wheel sector uses black. `keyboardFocusIndicatorColor` remains system-owned. The application explicitly uses Dark Aqua; the custom RGB values in frontmatter preserve the source's calibrated color components, rather than approximated screenshot hex values.

## Typography

All text uses `NSFont.systemFont`; the frontmatter records sizes in macOS points and weights corresponding to AppKit regular, medium, and semibold. Native pop-up and segmented controls retain AppKit typography.

The title is the largest label. The drop heading is the task invitation. Body, status, and selected filenames use the compact body role; custom buttons use the control roles. Wheel formats are larger than tool/action labels; the latter share space with SF Symbols. The wheel center pairs a semibold context label with a regular file count. Footer guidance is the smallest role.

## Layout

The non-resizable utility window has a content rectangle of **720 × 650 points**, with the content extending into a transparent titlebar. Outer horizontal margins are **32 points**, yielding **656 points** of usable width. This is native fixed AppKit geometry, without web breakpoints or a mobile layout.

The header contains the original CitrusDrop icon (Resources/CitrusDrop.icns), app name, subtitle, and a **120 × 28 point** language pop-up. A separator precedes the three native mode segments. The **656 × 180 point** drop view leads the task; two browse actions sit below it. Selected files precede an explicit operation label, the operation pop-up and a primary action named for the selected tool/action. Mode-specific copy remains visible even with no files selected. Progress and results share the status area. Finder setup, engine information, and result reveal occupy the footer above the keyboard hint.

The radial panel is **332 × 332 points** and is clamped to the current screen's visible frame. Its center follows the pointer when opened, subject to that clamp. Rendered wheel geometry uses a **154 point outer radius**, **60 point inner radius**, and **107 point label radius**. A disk inset by **9 points** backs the sectors. Sector gaps are angular (**1 degree**), not a fixed pixel width.

## Elevation & Depth

The main window and controls use tonal layering and thin boundaries rather than custom shadows. The radial menu is a transparent, borderless, nonactivating floating `NSPanel` at pop-up-menu level with the **native panel shadow enabled**. Its backing disk uses the window color at **0.99 alpha**. Do not substitute a fabricated CSS shadow or glow.

There are no authored decorative animation timings. Hover, press, selection, and drag feedback redraw immediately; the spinner and system UI retain native behavior.

## Shapes

Custom buttons use gently rounded corners and an inset fill; the drop area is a larger rounded rectangle with a **1 point** outline. The wheel is circular, with annular sectors and a quiet central disk. Native window corners, pop-ups, segments, and alerts remain AppKit-owned.

## Components

### Buttons

`ActionButton` draws primary and secondary fills from the frontmatter. Its fill is inset **1 point**. Enabled hover blends the resting background **8% toward white**; press blends it **16% toward black**. Disabled buttons use the disabled fill and native disabled text. A first-responder button draws a native focus-color stroke (**2 points**, inset **2 points**, radius **8 points**). Custom titles have **8 point** horizontal insets. Main browse/run buttons are **34 points** high; footer buttons are **30 points** high.

### Native controls and dialogs

`NSSegmentedControl` exposes Convert, Tools, and Actions with separated segments. `NSPopUpButton` provides the language and supported-operation choices. Native open panels, numeric input alerts, information/error alerts, and macOS Automation consent retain system styling and interaction. The language selection rebuilds the window and menus in Russian or English.

### File drop area

`FileDropView` draws its surface inset **3 points**, with a centered **32 point** SF Symbol, mode heading, format/tool explanation and file-selection invitation. Each mode has its own icon and copy. While dragging, its fill becomes `systemOrange` at **0.15 alpha**, and its outline becomes solid `systemOrange`. It exposes a localized accessibility group label.

### Radial menu

Only the selected sector uses `systemOrange`; selection may come from pointer hover, drag position, or arrow keys. Format names carry the content without redundant icons. Tool/action sectors pair localized labels with **18 point** SF Symbols. The center shows the localized mode and file count. Each sector exposes an accessibility button with a localized operation label; the group label also updates on language change. Return activates the keyboard selection; Escape dismisses the menu. The same operations are available in the main window.

### Status and results

The native spinner and shared text area communicate processing. The primary action becomes Cancel while busy. Completed outputs reveal a secondary Show results button. Preserve this state hierarchy rather than adding an ornamental success surface.

## Do's and Don'ts

### Do
- Do preserve the graphite/orange identity and the macOS system font.
- Do keep Russian and English controls within the implemented window geometry.
- Do use system semantic colors for native labels, focus, and disabled text.
- Do keep the wheel operations available through the main window as well.

### Don't
- Don't add ornamental animation, texture, glow, or large slogans.
- Don't replace native macOS controls or permission prompts with web or iOS conventions.
- Don't use copied Tangerine assets or promote QA sample images into product assets.

### Engine setup

A separate 540 × 360 point utility window shares the graphite/orange palette. It shows media and Office engine status, a single install action, progress and cancellation. It offers setup when engines are missing and updates available formats after installation without restarting.

The selected operation is remembered independently in Convert, Tools and Actions whenever it is supported by the current file selection. Language changes and completed processing retain that choice. Copy, duplicate, move and preview actions expose visible status; duplicate/move results can be revealed from the main window. Mode switching is disabled during conversion.
