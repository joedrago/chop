# AGENTS.md

Chop is a macOS-only, AppKit-native image editor with a `chop` CLI shim. From-scratch — no cross-platform abstraction layer. Bundle id `com.joedrago.chop`. Dual MIT / Apache-2.0.

## Build & dev loop

```sh
make generate   # regenerate Chop.xcodeproj from project.yml (gitignored)
make build      # debug build
make run        # build then launch Chop.app
make test       # xcodebuild test (Swift Testing)
make lint       # swift-format --strict
make format     # swift-format --in-place
make check      # lint + test — the local pre-commit gate
```

No IDE involved. Toolchain: `xcode-select --install` and `brew install xcodegen`.

## Where things live

```
project.yml                    # xcodegen spec; .xcodeproj is gitignored
Makefile, .swift-format
Resources/                     # Info.plist, Chop.icns, Assets.xcassets
Chop/                          # the .app target
  AppDelegate.swift, ChopDocument.swift, MainMenuController.swift
  Document/                    # NSDocument plumbing, window controller, toolbar
  Canvas/                      # MTKView subclass, inputs, marching ants, Metal
  Panels/                      # toolbox / info / status side palettes
  Tools/                       # Tool protocol + pan / zoom / rect-select
  Dialogs/                     # Resize and Save Options sheets
  Model/                       # pure data types — no AppKit imports
ChopCLI/main.swift             # `chop` shim; copied into Chop.app/Contents/MacOS/chop
ChopTests/                     # Swift Testing; mirrors Chop/ subfolders
```

The data-model `Document` (`Chop/Model/Document.swift`) is distinct from `ChopDocument` (the `NSDocument` subclass).

## Invariants

- **Never invoke `git` from the agent.** The harness blocks it; the maintainer owns all VCS. Reason from the working tree and the conversation, not from `git`.
- **macOS 14 Sonoma minimum.** Apple Silicon dev; universal build for Intel compatibility.
- **AppKit, programmatic.** No SwiftUI. No `.xib` / `.storyboard`. Menus, sheets, panels live in Swift source.
- **The data model imports no AppKit.** `Chop/Model/` is pure, testable Swift. AppKit lives outside it.
- **All edits go through `Action`s registered with `NSUndoManager`.** Layer pixel buffers are only mutated via `Action.apply`.
- **Layer dimensions always equal document dimensions.** Permanent property. Crop / Resize iterate layers and apply the same transform to each. Alpha covers the use cases that variable-size layers would otherwise address.
- **Single-layer assumption is current, not forever.** The data model is layer-aware (so multi-layer is additive when the time comes), but today every code path assumes `layers.count == 1` and may `assert` it. Adding multi-layer support is on the roadmap, not a no-go.
- **Color management is on.** `CGImage`s carry their source color space end-to-end; ColorSync converts to the display gamut. Wide-gamut and HDR work for free via EDR-enabled `CAMetalLayer`.
- **EXIF orientation: apply on load, drop on save.** No EXIF written. Other ancillary metadata (gAMA, text chunks, …) also dropped.
- **No untitled window on launch.** `applicationShouldOpenUntitledFile(_:)` returns `false`. There is no `File → New`.
- **Sticky window position.** All document windows share `setFrameAutosaveName("ChopDocumentWindow")`.
- **Native macOS document tabs.** `Show Tab Bar` / `⇧⌘T`, free with NSDocument.
- **All Swift is `swift-format`-formatted.** `make lint` fails on any unformatted file. Hand-formatting never happens. SwiftLint is not used.
- **Local-only.** No CI, no GitHub Actions, no code signing, no notarization, no DMG, no autoupdate. `make check` is the gate.
- **Single-instance via LaunchServices + AppleEvents.** The `chop` shim hands URLs to `NSWorkspace.open(_:withApplicationAt:configuration:)`, routed by `application(_:open:)`.
- **OS-standard About panel** (`NSApp.orderFrontStandardAboutPanel(_:)`) populated from `Info.plist`.

## Current scope

What ships today: open / save PNG and JPEG · pan, zoom (wheel-around-cursor, `.nearest` sampling) · rectangle selection with marching ants · crop · resize (nearest / bilinear / lanczos3) · undo/redo · `chop foo.png` opens in the running app · minimal above-canvas `NSToolbar`.

Not yet, but reasonable directions when the time comes: a Layers palette / multi-layer UX (the data model is already layer-aware), brushes / painting / color picker, additional formats (ImageIO already supports them — adding one is a UTType in Info.plist plus a small encoder-options sheet), a plugin system, public distribution (signing, notarization, DMG, autoupdate, CI). None of these are anti-goals; they are simply outside the present implementation.
