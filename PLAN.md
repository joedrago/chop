# Chop — Swift / macOS Plan

A simple, fast, **macOS-only** image editor written in Swift. CLI command: `chop`. App name: `Chop`.

This document is the rolling source of truth for design and scope. Edit it as decisions evolve.

---

## 1. Goals & invariants

- **macOS-only**, native through and through. Built with **AppKit + NSDocument + NSUndoManager + ImageIO + ColorSync + Metal**. No cross-platform abstraction layer.
- **macOS 14 Sonoma minimum.** Modern AppKit / Swift APIs available without `@available` ladders.
- **Headless dev loop.** The project is defined by a checked-in `project.yml` (consumed by `xcodegen`); the generated `Chop.xcodeproj` is gitignored. Build, lint, test, run, format — all via `make` targets that wrap `xcodebuild` + `swift-format`. **The Xcode IDE is never required.** The Xcode *toolchain* (compiler + SDKs, installable via the Command Line Tools or a full Xcode.app) is.
- **All Swift code is formatted by `swift-format`** (Apple's official formatter, bundled with the Swift toolchain) against the rules in `.swift-format` at the repo root. `make format` rewrites; `make lint` fails on any unformatted file. Hand-formatting never happens.
- **All UI code is programmatic AppKit**, not Interface Builder. No `.xib` / `.storyboard` files. Menus, sheets, dialogs, panels all live in `.swift` source — diff-friendly, editor-agnostic, and reviewable in a PR.
- **Always clean**: `make check` (build + lint + test) stays green locally. There is no CI in v1 (see §15.18); `make check` is the developer's pre-commit gate.
- **Never invoke `git`.** The Claude Code harness blocks `git` for the agent, so hooks, scripts, or Bash invocations that shell out to git will not work. All version-control operations (commits, branches, pushes, log inspection) are handled by the human maintainer; the agent reasons about state from the working tree and the conversation, not from `git`.
- **Feels like a Mac app**: native menus, native window tabbing, NSAlert sheets, NSOpenPanel / NSSavePanel, the standard About panel, automatic Recent Files, Cmd+Q quits via the OS, Cmd+W closes the document, dirty-state title-bar dot — all free with NSDocument.
- **Window position is sticky.** Every document window shares the autosave name `ChopDocumentWindow` (`NSWindow.setFrameAutosaveName(_:)`); AppKit persists the frame across launches and cascades simultaneous windows by 25 pts so they don't overlap. The next document you open appears where you left the last one.
- **Paint.NET-flavored UI**: main canvas centered; tool palette as a left sidebar; tool-options on the right; room for more palettes (Info, History, Color, …) without UI surgery.
- **Fast pan / zoom** via Metal with `.nearest` magnification. The point under the cursor stays fixed under the cursor while the wheel turns.
- **Color-managed by default.** Loaded images keep their CGImage color space (sRGB / Display P3 / BT2020 / …); ColorSync converts to the display's profile at draw time. **Wide-gamut and HDR work for free** — we light up an EDR-enabled `CAMetalLayer` and let macOS render the source image in its native gamut.
- **All edits are Actions** registered with `NSUndoManager`. Unlimited undo. Memory cost is acceptable.
- **No window on launch.** Launching Chop with no file shows just the menu bar (and a Dock icon) — no untitled window. An "empty" image document has no natural shape (width/height undefined), so we'd rather the user reach for File → Open or `chop foo.png` than stare at a placeholder. Implemented by returning `false` from `NSApplicationDelegate.applicationShouldOpenUntitledFile(_:)`.
- **License**: dual MIT OR Apache-2.0.

### Layers in v1

The data model supports layers from day one. Every loaded image lives in a single `Background` layer; saving flattens layers into one `CGImage`; rendering composites through the same path. v1 ships with **no Layers palette** and no UI for adding/removing/reordering — the document just always has exactly one layer. Future multi-layer work is additive, not a rewrite.

### What we explicitly do *not* commit to in v1

- Multi-layer UX: Layers palette, masks, blend modes, opacity sliders, layer-specific tools.
- Brush tools, painting, color picker.
- Plugin system. New formats are added in-tree (a new UTType in Info.plist + small encode/decode plumbing).
- SwiftUI. The chrome and the canvas are both AppKit. We trade SwiftUI Previews' hot-reload for AppKit's predictability and battle-tested image-editor lineage; iteration on layout is via Interface Builder + programmatic NSView.

---

## 2. Tech stack

| Concern              | Choice                                   | Why |
|----------------------|------------------------------------------|-----|
| App framework        | AppKit + NSDocument                      | Battle-tested for serious Mac image editors. Free File menu, Recent Files, autosave-in-place, dirty-state title, close-confirm, NSUndoManager integration. |
| Canvas               | `MTKView` (NSView subclass)              | GPU-accelerated rendering via Metal; `.nearest` sampler for crisp pixels at zoom; opt-in EDR for HDR display. |
| Pixel storage        | `CGImage` (per layer)                    | Canonical pixel state. ImageIO produces them; CGContext re-creates them after edits. ColorSync makes them color-managed end-to-end. |
| Codecs               | ImageIO (`CGImageSource` / `CGImageDestination`) | PNG, JPEG, HEIF/HEIC, WebP, AVIF, JPEG XL, TIFF, GIF "for free" (system-supported on macOS 14). ICC preserved end-to-end. EXIF easily inspected. v1 ships scoped to PNG + JPEG; new formats are one Info.plist entry plus an encoder-options sheet (if any). |
| Undo / redo          | `NSUndoManager`                          | The OS-standard undo manager; auto-fills Edit menu's Undo/Redo with dynamic action labels. |
| File dialogs         | `NSOpenPanel` / `NSSavePanel`            | Native, mature, sheet-attached to the document window. |
| About panel          | `NSApp.orderFrontStandardAboutPanel(_:)` | OS-standard panel; populated from Info.plist. |
| Color management     | ColorSync (implicit via CG)              | Works because we keep CGImage's source color space and let CG draw to the display. |
| HDR rendering        | EDR via `CAMetalLayer.wantsExtendedDynamicRangeContent` | Free EDR rendering when the source CGImage carries HDR pixels. |
| CLI parsing          | `swift-argument-parser`                  | Apple's CLI parser. Trivial for `chop [files...]`. |
| Logging              | `os.Logger` (unified log)                | Native, integrated with Console.app. |
| IPC / single-instance | AppleEvents via `NSApplicationDelegate.application(_:open:)` | OS-level: `open -a Chop foo.png` routes to the running instance. No socket plumbing. |
| Project generation   | `xcodegen`                                | Reads `project.yml` and produces `Chop.xcodeproj`. The project bundle is gitignored; only the spec is committed. |
| Build driver         | `xcodebuild` (CLI)                        | Build, test, archive, exportArchive — all from the terminal. No IDE. |
| Task runner          | `make` (Makefile)                         | One-line wrappers for the common workflows: `make build`, `make test`, `make lint`, `make format`, `make run`, `make archive`. |
| Tests                | Swift Testing (`@Test` attribute)         | Modern Swift test framework, available on macOS 14. Run via `xcodebuild test`. |
| Formatter            | `swift-format`                            | Apple's official formatter, bundled with the Swift toolchain. Auto-fix; configured via `.swift-format` at the repo root. `make format` rewrites; `make lint` fails if anything is unformatted. |
| Editor support       | `sourcekit-lsp`                           | Ships with the Xcode toolchain. VS Code / Neovim / Helix / etc. get Swift completion + diagnostics + go-to-definition without Xcode. |

### Project structure

Single Xcode project (`Chop.xcodeproj`) with **three targets** — the minimum a TextEdit-class macOS app with a CLI helper would have:

- **`Chop`** — the `.app` target. Everything: UI, canvas, tools, NSDocument subclass, AppDelegate, AppleEvent routing, **and the data model** (in a `Model/` subfolder). No separate "core" framework — Swift's `@testable import` makes that split unnecessary.
- **`chop`** *(target name `ChopCLI`)* — the command-line shim. Tiny `main.swift` that calls `NSWorkspace.open(...)`. Built as a separate executable, then copied into `Chop.app/Contents/MacOS/chop` by a build phase so it ships inside the bundle.
- **`ChopTests`** — single Swift Testing target. Subfolders organize unit / integration / round-trip tests; `@testable import Chop` reaches the data model and any internal app types directly.

### Test layout convention

Swift Testing's `@Test` attribute. One test file per logical unit (`ImageBufferTests.swift`, `DocumentTests.swift`, …). Subfolders inside `ChopTests/` organize by area (`Model/`, `IO/`, `Integration/`). No multiplexed test targets — one is enough.

---

## 3. Module layout

```
Chop.xcodeproj                     # generated from project.yml; gitignored
project.yml
Makefile
.swift-format
.gitignore
LICENSE-MIT
LICENSE-APACHE
README.md
SWIFT.md

Resources/                         # bundled into Chop.app at build time
  Info.plist
  Chop.icns
  Assets.xcassets/

Chop/                              # the .app target
  AppDelegate.swift                # NSApplicationDelegate, AppleEvent routing, MainMenu
  ChopDocument.swift               # NSDocument subclass; thin wrapper over Model.Document
  Document/
    ChopDocument+Open.swift        # read(from:ofType:)
    ChopDocument+Save.swift        # data(ofType:)
    ChopDocument+Window.swift      # window controller wiring
  Canvas/
    CanvasView.swift               # MTKView subclass; renders document.composite()
    CanvasInputs.swift             # NSResponder methods → tool dispatch
    MarchingAnts.swift             # CAShapeLayer overlay
    MetalRenderer.swift            # texture upload + draw call
  Panels/
    ToolboxView.swift              # left sidebar
    ToolOptionsView.swift          # right sidebar
    InfoPaletteView.swift          # cursor + selection coords
    StatusBarView.swift            # zoom %
  Tools/
    Tool.swift                     # protocol
    SelectRectTool.swift
    PanTool.swift
    ZoomTool.swift
  Dialogs/
    ResizeSheet.swift              # NSPanel sheet
    SaveOptionsSheet.swift         # PNG / JPEG knobs
  Model/                           # the data model — pure types, no AppKit imports
    ImageBuffer.swift              # CGImage wrapper + helpers
    Layer.swift
    Document.swift                 # data model (distinct from ChopDocument NSDocument subclass)
    DocumentSnapshot.swift
    Selection.swift
    ViewState.swift
    Geometry.swift                 # Rect, Vec2, view math
    Action.swift                   # protocol
    Actions/
      SetSelectionAction.swift
      CropAction.swift
      ResizeAction.swift
    Filters/
      ResampleFilter.swift         # enum
      Resize.swift                 # nearest / bilinear / lanczos3

ChopCLI/                           # the `chop` shim — separate executable target
  main.swift                       # ~30 lines; calls NSWorkspace.open

ChopTests/                         # one test target; @testable import Chop
  Model/
    ImageBufferTests.swift
    DocumentTests.swift
    ResizeTests.swift
  IO/
    RoundtripPNGTests.swift
    RoundtripJPEGTests.swift
    EXIFOrientationTests.swift
  Integration/
    AppleEventDispatchTests.swift
    NSDocumentLifecycleTests.swift
```

The data model lives inside the app target's `Model/` folder — it doesn't import AppKit, so it's still purely testable, but it doesn't need its own framework wrapper to be reachable. `ChopDocument` (the NSDocument subclass) wraps `Model.Document` and bridges to AppKit's NSDocument lifecycle.

The CLI shim builds to a `chop` executable; a "Copy Files" build phase on the `Chop` target embeds it into `Chop.app/Contents/MacOS/chop`. The "Install Command Line Tool…" menu item then symlinks that to `/usr/local/bin/chop`.

---

## 4. Data model (`Chop/Model/`)

```swift
// ImageBuffer.swift
public struct ImageBuffer {
    public let cgImage: CGImage             // canonical pixel state; carries its own color space
    public var width: Int  { cgImage.width }
    public var height: Int { cgImage.height }
    public var colorSpace: CGColorSpace? { cgImage.colorSpace }
}

// Layer.swift
public struct Layer: Identifiable {
    public let id: LayerId
    public var name: String                 // "Background", "Layer 2", …
    public var visible: Bool                // v1: always true
    public var opacity: Float               // 0…1; v1: always 1.0
    public var blend: BlendMode             // v1: always .normal
    public var pixels: ImageBuffer          // dimensions MUST match Document.{width, height}
}

public enum BlendMode { case normal /* future: multiply, screen, overlay, … */ }

// Document.swift  (data model — separate from the NSDocument subclass)
public final class Document {
    public private(set) var width: Int
    public private(set) var height: Int
    public private(set) var layers: [Layer]            // bottom-up; v1 invariant: layers.count == 1
    public var activeLayer: LayerId
    public var selection: Selection
    public var view: ViewState
    public private(set) var textureRevision: UInt64    // bumped on any pixel/layer/dim change

    public func composite() -> CGImage { /* v1: layers[0].pixels.cgImage */ }
    public func flatten() -> CGImage  { composite() }   // alias for the save path

    public func snapshot() -> DocumentSnapshot
    public func restore(from snap: DocumentSnapshot)    // also bumps textureRevision
}

// Selection.swift
public enum Selection: Equatable {
    case none
    case rect(IRect)                        // integer-aligned image-space rectangle, document-wide
}

// ViewState.swift
public struct ViewState {
    public var zoom: Float                  // pixels-on-screen per image-pixel; 1.0 = 100%
    public var center: SIMD2<Float>         // image-space coordinate at the viewport's center
}
```

All edits go through `Action`s (see §7) so layer pixel buffers are only mutated via an action's `apply`.

### Layer-model decisions for v1

- **Layer dimensions always match the document.** Every `Layer.pixels` is exactly `width × height`. Crop / Resize iterate layers and apply the same transform to each. This is permanent, not v1-only — alpha covers the use cases that variable-size layers would otherwise address.
- **Selection is document-wide**, not per-layer.
- **Single-layer invariant in v1.** `Document.fromImage(...)` constructs one `Layer` named "Background" with `visible=true, opacity=1, blend=.normal`. Code that operates over layers (composite, crop, resize, snapshot) is written generically and `assert`s the invariant where it relies on it.

---

## 5. Codecs (ImageIO directly, no abstraction)

No `Format` protocol. The `NSDocument` subclass calls ImageIO directly. Adding a new format = declare a new UTType in Info.plist's `CFBundleDocumentTypes` + a small encoder-options sheet if it has knobs.

### Reading

```swift
override func read(from data: Data, ofType typeName: String) throws {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw ChopError.decode }

    // Apply EXIF Orientation (ImageIO surfaces it but doesn't bake it).
    let oriented = applyEXIFOrientation(cgImage, source: source)

    self.document = Document.fromImage(oriented, name: "Background")
}
```

Document types declared in Info.plist (`CFBundleDocumentTypes`, with `LSItemContentTypes` for the UTI and `CFBundleTypeExtensions` for the recognised filenames):

| UTI | Read | Write | Extensions accepted on open | Default extension on save |
|-----|:----:|:-----:|-----------------------------|---------------------------|
| `public.png`  | ✓ | ✓ | `png` | `.png` |
| `public.jpeg` | ✓ | ✓ | `jpg`, `jpeg`, `jpe` | **`.jpg`** |

`.jpg` is the canonical save extension — listed first in `CFBundleTypeExtensions`, and when `NSSavePanel` needs to pick an extension on its own (e.g. on Save As where the user switches the format from PNG to JPEG), the proposed filename uses `.jpg`. Files arriving with `.jpeg` or `.jpe` on open are read fine and retain their on-disk name. (Note: `public.jpeg` is Apple's UTI for the JPEG format and is independent of which extension the file uses on disk; it's not a filename.)

### Writing

```swift
override func data(ofType typeName: String) throws -> Data {
    let utt = UTType(typeName)!
    let mut = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(mut, utt.identifier as CFString, 1, nil) else {
        throw ChopError.encode
    }
    let opts = encodeOptions(for: typeName)   // see §9 for option mapping
    CGImageDestinationAddImage(dest, document.flatten(), opts as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { throw ChopError.encode }
    return mut as Data
}
```

### EXIF orientation

ImageIO exposes orientation via `kCGImagePropertyOrientation` but does **not** bake it into the pixel data. On load we read the tag, apply the corresponding affine transform via CGContext (or CIImage), and produce a new oriented CGImage. The Document doesn't carry EXIF further; we never write it on save.

### Color management

We **keep** the CGImage's source color space — sRGB, Display P3, BT2020, etc. — so ColorSync can color-manage the canvas. The display's color profile is queried via `NSScreen.colorSpace`; a CGImage drawn into a `CAMetalLayer` is color-converted by CG to the display gamut. Wide-gamut and HDR images render correctly without color code on our side.

On save, `CGImageDestination` re-embeds the source color space. Round-trips preserve color information.

The opposite path (force-convert to sRGB on load, discard the embedded profile) is actually *more* code on macOS than letting CG do its thing — we'd be writing logic to throw away the very metadata that buys us free WCG / HDR.

---

## 6. Pan / zoom / rendering

### Math

Image-space `p` ↔ screen-space:
```
screen(p) = viewportCenter + (p - view.center) * view.zoom
image(s)  = view.center + (s - viewportCenter) / view.zoom
```

Zoom-around-cursor invariant (cursor screen `s`, current zoom `z1`, target zoom `z2`):
```
view.center_new = view.center + (s - viewportCenter) * (1/z1 - 1/z2)
```
Same formula whether the input is the wheel, the zoom tool drag, or `Cmd+=` / `Cmd+-`.

### Rendering path

`CanvasView` is an `MTKView` subclass. Each `Document` has a lazily allocated `MTLTexture` keyed off `textureRevision`; when the revision advances, we re-upload from `document.composite()`.

```swift
final class CanvasView: MTKView {
    var document: Document?
    private var lastRevision: UInt64 = 0
    private var texture: MTLTexture?

    override func draw(_ dirtyRect: NSRect) {
        guard let doc = document else { return }
        if doc.textureRevision != lastRevision {
            texture = uploadTexture(from: doc.composite())  // CG → MTLTexture
            lastRevision = doc.textureRevision
        }
        // Render texture as a quad with a sampler whose magFilter = .nearest.
        // Position/size driven by view.center and view.zoom.
    }
}
```

For HDR / wide-gamut output:
```swift
canvasView.colorPixelFormat = .rgba16Float
(canvasView.layer as? CAMetalLayer)?.wantsExtendedDynamicRangeContent = true
canvasView.layer?.colorspace = nil   // let CG infer from layer & display
```

Selection overlay: a sibling `CAShapeLayer` with `lineDashPattern = [4, 4]` and a `CABasicAnimation` on `lineDashPhase` for marching ants. Animation runs only while a selection exists.

Out-of-canvas regions: a checkerboard pattern drawn directly in the Metal pipeline (or as a tiled CALayer behind the canvas).

Scrollbars: `NSScroller` instances around the canvas, driving `view.center`. We don't use `NSScrollView` because we drive zoom independently.

### Inputs that affect view

- **Wheel over canvas**: `zoom *= exp(delta * k)`, then zoom-around-cursor.
- **Pan / Hand tool**: drag = move `view.center` by `-deltaScreen / zoom`.
- **Zoom tool**: drag-vertically = continuous zoom, anchored at the click point.
- **Spacebar held**: temporary Pan-tool override.
- **Cmd+0**: fit-to-window. **Cmd+1**: 100%.
- **NSScroller drag** → update `view.center`.

View is per-document; the `Document` carries it, so switching windows / tabs restores the prior view exactly.

---

## 7. Actions, history, undo / redo

`NSUndoManager` is the engine; `Action` is our content layer.

```swift
public protocol Action {
    var label: String { get }                        // shown in Edit > Undo X / Redo X
    func apply(to document: Document) throws
    func revert(from document: Document) throws
}
```

The NSDocument subclass owns the dispatch site and registers each action with the undo manager:

```swift
func commit(_ action: Action) throws {
    let snap = document.snapshot()
    try action.apply(to: document)
    undoManager?.registerUndo(withTarget: self) { doc in
        doc.document.restore(from: snap)
        doc.undoManager?.registerUndo(withTarget: doc) { redoTarget in
            try? redoTarget.commit(action)            // redo
        }
    }
    undoManager?.setActionName(action.label)         // populates "Undo Crop", "Redo Resize"
}
```

The undo manager auto-handles Edit menu state. No work for us.

### Action scope

- **Document-scoped** — changes dimensions, the layer set, the selection, the active-layer pointer. v1 actions are all document-scoped: `SetSelection`, `Crop`, `Resize`. Pixel-mutating ones revert via a `DocumentSnapshot`.
- **Layer-scoped** — changes a single layer's pixels (future paint / fill / filter actions). Reverts by stashing the affected layer's prior `ImageBuffer` keyed by `LayerId`.

### Memory model

Actions snapshot whatever they need at apply time. RAM is cheap; correctness > cleverness. `CropAction` and `ResizeAction` capture a `DocumentSnapshot` (every layer's pixels + canvas dims + active-layer pointer); `SetSelectionAction` keeps the prior `Selection` only. Snapshotting all layers is wasteful when there's only one — and it's the right shape once there's more than one — so we eat the trivial cost now to avoid changing the action API later. Optimization (delta encoding, COW, on-disk spill) is a self-contained later task that doesn't change the protocol.

### Initial action set

- `SetSelectionAction`
- `CropAction` — iterates `doc.layers`, crops each `Layer.pixels` to the selection rect, updates dimensions.
- `ResizeAction` — iterates `doc.layers`, resizes each via the chosen filter, updates dimensions.

---

## 8. Tools

`Tool` protocol; the active tool is per-Document. The Toolbox renders one button per tool.

```swift
public protocol Tool {
    var id: ToolId { get }
    var name: String { get }
    var shortcut: KeyEquivalent? { get }
    var cursor: NSCursor { get }

    func mouseDown(_ event: NSEvent, ctx: inout ToolContext)
    func mouseDragged(_ event: NSEvent, ctx: inout ToolContext)
    func mouseUp(_ event: NSEvent, ctx: inout ToolContext)
    func keyDown(_ event: NSEvent, ctx: inout ToolContext)
    func paintOverlay(in context: CGContext, view: CanvasView)
}
```

`ToolContext` exposes the NSDocument subclass so tools can `commit(action)`. Tools never mutate the document directly — they construct actions and commit them. Free undo for everything.

### v1 tools

- **Rectangle Select** (`R`) — drag to define a rectangle. On release, commit a `SetSelectionAction`. Shift / Alt modifiers later — v1 just replaces.
- **Pan / Hand** (`H`, also active while Space held) — moves `view.center`.
- **Zoom** (`Z`) — drag-to-zoom anchored at the click point.

---

## 9. Menus & dialogs

Native `NSMenu`, built programmatically in `AppDelegate`. Cocoa's responder chain wires menu items to first-responder methods on the NSDocument subclass — no `MenuCommand` enum needed; the menu *is* the dispatch.

```
Chop      About Chop                         (NSApp.orderFrontStandardAboutPanel(_:))
          Settings…              ⌘,
          Services
          Hide Chop              ⌘H
          Hide Others            ⌥⌘H
          Show All
          Quit Chop              ⌘Q
File      Open…                  ⌘O
          Open Recent            ▸                (auto-populated by NSDocumentController)
          Close                  ⌘W
          Save                   ⌘S
          Save As…               ⇧⌘S
          Revert to Saved
Edit      Undo                   ⌘Z              (auto-labeled by NSUndoManager)
          Redo                   ⇧⌘Z             (auto-labeled by NSUndoManager)
          Deselect               ⌘D
Image     Resize…                ⌘R
          Crop                                    (enabled only when .rect selection active)
View      Zoom In                ⌘=
          Zoom Out               ⌘-
          Actual Size            ⌘1
          Fit to Window          ⌘0
          Show Tab Bar           ⇧⌘T              (native window-tabbing toggle)
Window    (auto-populated by AppKit)
Help      Chop Help
```

There is intentionally no **File → New** in v1. An empty image document has no natural width/height; rather than invent a default, we route document creation through Open or the CLI. (See §15 open question for a possible future "New… → size sheet" flow.)

Menu items target the responder chain via standard selectors (`@IBAction func crop(_:)`, `@IBAction func deselect(_:)`, …). NSDocument auto-disables items for which the document doesn't have a target (e.g. Crop without a selection).

### Resize sheet

A `NSPanel` attached as a sheet to the document window:

- Pixel-mode width/height inputs **OR** percentage-mode inputs (radio).
- Lock-aspect-ratio toggle (chain icon).
- Filter dropdown: Nearest, Bilinear, Lanczos3.
- Live preview of new dimensions and approximate megapixels.
- OK / Cancel.

OK commits a `ResizeAction`. Cancel does nothing.

### Save Options sheet

Runs after `NSSavePanel` returns a URL. ImageIO encoder option mapping:

| Knob | ImageIO key |
|------|-------------|
| JPEG quality | `kCGImageDestinationLossyCompressionQuality` (0…1) |
| JPEG progressive | `kCGImagePropertyJFIFIsProgressive` |
| JPEG chroma subsampling | *(not directly exposed by ImageIO)* — system default in v1 |
| PNG interlace | `kCGImagePropertyPNGInterlaceType` |
| PNG compression level | *(not directly exposed by ImageIO)* — system default in v1 |

**Limitation:** ImageIO exposes most encoder knobs but not all. JPEG chroma subsampling and PNG compression level fall back to system defaults. If a user later needs granular control, we can swap a Swift PNG/JPEG library in for the affected formats. Not a v1 problem.

---

## 10. CLI behavior & single-instance

LaunchServices + AppleEvents do the heavy lifting; almost nothing custom is required.

### Surface

```
chop                         # ensures Chop.app is running, focuses it
chop foo.png bar.jpg         # opens these files in the running Chop.app, returns immediately
chop --version
chop --help
```

The terminal returns immediately in every case.

### `chop` shim implementation

A separate Swift target (`ChopCLI`) builds a tiny command-line binary, ~30 lines:

```swift
import AppKit
import ArgumentParser

@main
struct ChopShim: ParsableCommand {
    @Argument(parsing: .remaining) var files: [String] = []

    func run() throws {
        let urls = files.map { URL(fileURLWithPath: $0).standardizedFileURL }
        let appURL = URL(fileURLWithPath: "/Applications/Chop.app")
        let cfg = NSWorkspace.OpenConfiguration()
        if urls.isEmpty {
            NSWorkspace.shared.openApplication(at: appURL, configuration: cfg) { _, _ in }
        } else {
            NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: cfg) { _, _ in }
        }
    }
}
```

`NSWorkspace.open` returns immediately. LaunchServices ensures only one instance of Chop.app runs at a time (the OS default for LaunchServices-launched bundles); each URL arrives at the running app via an `kAEOpenDocuments` AppleEvent, which AppKit routes to:

```swift
func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }
}
```

That's the entire IPC story. No Unix sockets, no double-fork detach, no `--gui-server` flag, no stale-socket cleanup.

### Drag-and-drop

`CanvasView` registers `[.fileURL]` as a drag-destination type and forwards drops to the same `application(_:open:)` flow.

### Finder double-click

Routes through `application(_:open:)` automatically via AppleEvents. Free.

### CLI install

The `chop` shim is shipped inside the bundle at `/Applications/Chop.app/Contents/MacOS/chop`. The app exposes a `Chop > Install Command Line Tool…` menu item that symlinks it into `/usr/local/bin/chop` (with an authorization prompt). Optional Homebrew cask deferred past v1.

---

## 11. Save / load

NSDocument's lifecycle handles ~90% of this:

- **Open (Cmd+O)** → `NSOpenPanel` → `NSDocumentController` dispatches to `read(from:ofType:)` on a new `NSDocument`.
- **Save (Cmd+S)** → `NSDocumentController` calls `data(ofType:)`, writes to the document URL, clears dirty state.
- **Save As (Cmd+Shift+S)** → `NSSavePanel` → optional encoder-options sheet → `data(ofType:)`.
- **Recent Files (File > Open Recent)** → auto-populated by `NSDocumentController`.
- **Close while dirty** → free `NSAlert` "Save / Don't Save / Cancel" sheet via `canClose(...)`.
- **Quit while any document dirty** → free; `NSDocumentController.reviewUnsavedDocuments` handles it.

EXIF orientation: applied on load (§5). ICC: preserved on the `CGImage` end-to-end. EXIF metadata dropped on save. Other ancillary metadata (gAMA, text chunks, …) dropped on load and not written.

Errors at any stage surface as a sheet `NSAlert` and a `Logger.error` message.

---

## 12. Build, lint, format

The dev loop runs out of `Makefile` at the repo root — a thin wrapper around `xcodegen` + `xcodebuild` + `swift-format`. Phony targets:

| Target | What it does |
|--------|--------------|
| `make generate` | `xcodegen generate` from `project.yml` → `Chop.xcodeproj`. The `.xcodeproj` is gitignored. |
| `make build` | Debug build. Auto-regenerates the project if `project.yml` is newer. |
| `make run` | Build, then `open` the resulting `.app`. |
| `make test` | `xcodebuild test`. |
| `make lint` | `swift-format lint --strict` — fails if any file is unformatted. |
| `make format` | `swift-format format --in-place` — auto-fix every `.swift` file in the tree. |
| `make check` | `lint` + `test` — the developer's pre-commit gate. |
| `make clean` | Remove `build/` and the generated `.xcodeproj`. |

There is no CI. `make check` is run by hand before commits; if a regression slips in, the next `make check` will catch it. (See §15.18 for the rationale.)

Formatting rules live in `.swift-format` at the repo root. `make format` is the canonical "make this file conform" command; nobody hand-formats anything. `make lint` is the "is everything conformant?" check.

Toolchain prerequisites (installed once, system-wide):

```sh
xcode-select --install     # Apple Swift compiler + SDKs (also ships swift-format)
brew install xcodegen      # project-spec generator
```

No Xcode IDE involvement at any point. SwiftLint is **not** required — `swift-format` covers formatting; if you later want extra style/correctness rules (e.g. force-unwrap bans), SwiftLint can be layered on as an optional add-on.

---

## 13. Packaging

**v1 is local-only.** `make build` (or `make run`) produces a `Chop.app` that runs on the maintainer's Mac. No code signing, no notarization, no `.dmg`, no autoupdate, no GitHub Actions release workflow — none of these are wired up, and none are gating for v1. If/when public distribution becomes a goal, that is a self-contained later body of work; the architecture doesn't need to anticipate it now.

The build is **universal** (x86_64 + arm64) so the unsigned `.app` runs on Intel as well as Apple-Silicon Macs, even though dev iteration is exclusively on Apple Silicon (M4). Universal adds negligible friction at this scale.

### App icon

The app icon will be generated from a single hi-res master PNG that the project owner will supply. Procedure:

1. Owner provides `Chop-master.png` at **1024×1024** (preferred) or 512×512 (acceptable; @2x at the 512pt size will rely on upscaling).
2. We script the iconset generation:
   ```sh
   mkdir Chop.iconset
   sips -z 16   16   Chop-master.png --out Chop.iconset/icon_16x16.png
   sips -z 32   32   Chop-master.png --out Chop.iconset/icon_16x16@2x.png
   sips -z 32   32   Chop-master.png --out Chop.iconset/icon_32x32.png
   sips -z 64   64   Chop-master.png --out Chop.iconset/icon_32x32@2x.png
   sips -z 128  128  Chop-master.png --out Chop.iconset/icon_128x128.png
   sips -z 256  256  Chop-master.png --out Chop.iconset/icon_128x128@2x.png
   sips -z 256  256  Chop-master.png --out Chop.iconset/icon_256x256.png
   sips -z 512  512  Chop-master.png --out Chop.iconset/icon_256x256@2x.png
   sips -z 512  512  Chop-master.png --out Chop.iconset/icon_512x512.png
   sips -z 1024 1024 Chop-master.png --out Chop.iconset/icon_512x512@2x.png
   iconutil -c icns Chop.iconset -o Chop.icns
   ```
3. Drop `Chop.icns` into the Xcode project's `Assets.xcassets` (or set `CFBundleIconFile` in Info.plist directly).

Tracked as a Phase 8 / polish deliverable. Until the master is supplied, the build uses Xcode's default app-template icon.

---

## 14. Phased plan

Each phase is a coherent merge unit. Names are working titles; PRs can be smaller. NSDocument + NSUndoManager + ImageIO carry a chunk of the plumbing for free, which keeps the phase count modest.

**Phase 0 — Skeleton.** `project.yml`, Makefile, `.swift-format`, `.gitignore`. App target with `NSDocument` scaffolding and `applicationShouldOpenUntitledFile` returning `false`. `ChopCLI` binary target with a hello-world `main.swift`. App launches with menu bar visible and no window — File menu is reachable; Open does nothing yet. Local `make check` green from day one. License files. README stub.

**Phase 1 — Open / Display.** `read(from:ofType:)` reads a CGImage via ImageIO with EXIF orientation baked in. Single-layer data model in `Chop/Model/`. `CanvasView` (MTKView) displays the image at 100% with `.nearest` sampling. PNG and JPEG document types declared in Info.plist. Drag-and-drop onto the window opens files. Color-managed: a Display-P3 image looks right on a P3 display. Round-trip tests for ImageIO load.

**Phase 2 — Pan / zoom.** View math. Wheel zoom-around-cursor. Pan tool. Zoom tool. NSScroller scrollbars. Status bar shows zoom %.

**Phase 3 — Selection + marching ants.** `Selection`, `SetSelectionAction`. Rectangle Select tool. `CAShapeLayer` dashed overlay with marching-ants animation. Info palette shows cursor coords + selection rect.

**Phase 4 — Undo + Crop.** `Action` protocol; `NSUndoManager` wiring. `SetSelectionAction`, `CropAction`. Edit menu auto-shows "Undo X" / "Redo X" labels. Image > Crop enabled only when selection is active. Fuzz-test undo/redo sequencing against the data model.

**Phase 5 — Resize.** Resize sheet. Filters (nearest / bilinear / lanczos3) implemented in `Chop/Model/Filters/`. `ResizeAction`.

**Phase 6 — Save with options.** `data(ofType:)` writes via CGImageDestination. Save Options sheet for PNG / JPEG knobs. Tests verify color-space and orientation correctness on round-trip.

**Phase 7 — CLI + AppleEvents.** ChopCLI binary built; "Install Command Line Tool…" menu item symlinks it to `/usr/local/bin/chop`. `application(_:open:)` AppleEvent wiring. Verified: `chop foo.png` from the terminal returns immediately and opens the file in the running app (or a freshly-launched one).

**Phase 8 — Polish.** About Chop panel populated from Info.plist. All keyboard shortcuts wired. Native window tabbing enabled (`Show Tab Bar`). Minimal NSToolbar stub above the canvas (Open, Save, tool buttons, view-mode controls). Settings stub. App icon: generate `Chop.icns` from the supplied master PNG and wire it into `Info.plist` / `Assets.xcassets`.

History palette, Layers palette, additional tools, color picker, and additional formats are *not* in v1. Public distribution (code signing, notarization, `.dmg`, autoupdate, CI) is deferred indefinitely — v1 is local-only. The architecture leaves clean seams for all of these.

---

## 15. Decisions log

Load-bearing choices already made. The rationale lives here so future-us doesn't have to re-derive it.

1. **Bundle id `com.joedrago.chop`.** Reverse-DNS using the project owner's GitHub identity.
2. **macOS-only.** No cross-platform abstraction layer; AppKit and friends used directly.
3. **macOS 14 Sonoma minimum.** Modern AppKit + Swift Concurrency + Swift Testing available without `@available` ladders. Covers the large majority of currently-supported Macs.
4. **AppKit, not SwiftUI.** Battle-tested for image editors; maximum control over the canvas and tooling. Trade: no SwiftUI Previews — iteration on chrome is via Interface Builder + Xcode build/run.
5. **NSDocument + NSUndoManager as the document/undo backbone.** Free File menu plumbing, Recent Files, autosave-in-place, dirty-state title, close-confirm, undo with dynamic menu labels. The cost of reimplementing those would be high; the cost of using them is near zero.
6. **ImageIO directly, no `Format` protocol abstraction.** ImageIO is comprehensive and idiomatic on macOS; an abstraction layer wouldn't earn its keep. Easy to refactor in if a future requirement demands it (e.g. an encoder knob ImageIO doesn't expose).
7. **Color management on by default.** CGImage carries its source color space end-to-end; ColorSync converts to the display gamut at draw time. Wide-gamut and HDR images render in their native gamut. We never strip ICC on load and we re-embed the source profile on save. (See §5.)
8. **EXIF orientation — apply on load, drop, never write.** Phone JPEGs carry an `Orientation` tag rather than physically rotated pixels. We read the tag, apply the rotate/flip via CGContext / CIImage to the decoded buffer, and discard EXIF. Saved files carry no EXIF. (See §5.)
9. **Layer dimensions — always equal to document dims, forever.** Permanent property, not v1-only. Alpha covers the use cases that variable-size layers would otherwise address; per-layer dimensions would be a misfeature for a Paint.NET-flavored tool.
10. **Single-layer invariant in v1.** The data model is layer-aware (so the eventual multi-layer feature is additive, not a rewrite), but every code path in v1 assumes `layers.count == 1` and may `assert` it.
11. **Native menus and dialogs.** Cocoa's responder chain wires menu items to first-responder methods on the NSDocument subclass — no custom command-enum dispatch needed.
12. **Hi-DPI — native.** AppKit handles `convertToBacking(_:)`; Metal handles drawable scale; NSScreen surfaces backing scale and color profile.
13. **Single-instance via LaunchServices + AppleEvents.** No custom socket plumbing. The `chop` CLI shim hands URLs to `NSWorkspace.open(_:withApplicationAt:configuration:)`, which routes them to the running app's `application(_:open:)` delegate.
14. **No window on launch; menu bar only.** `applicationShouldOpenUntitledFile(_:)` returns `false`. An "empty" image document has no natural width/height — placeholder dimensions would be a guess and inventing a New-Document size sheet is scope-creep for v1. The user reaches for File → Open, drag-and-drop, or `chop foo.png` instead. There is intentionally no File → New in v1.
15. **Sticky window position.** All document windows share one `setFrameAutosaveName("ChopDocumentWindow")`; AppKit persists the frame to `NSUserDefaults` and restores it on the next document open, cascading simultaneous windows. Per-document position memory (heavier `NSWindowRestoration` work) is post-v1.
16. **Native macOS document tabs.** AppKit's `Show Tab Bar` / `⇧⌘T` is the idiomatic Mac path and is free with NSDocument. v1 adopts it; OS integration (drag-out-to-window, merge-all-windows, "Move Tab to New Window") comes for free. No custom in-window tab strip.
17. **Universal binary (x86_64 + arm64).** v1 ships a universal build so the unsigned `.app` runs on Intel as well as Apple-Silicon Macs. Dev iteration is exclusively on Apple Silicon (M4); universal adds negligible build-time and binary-size friction at this scale.
18. **No CI, no public distribution in v1.** The bar is "build and run on the maintainer's Mac." No GitHub Actions, no code signing, no notarization, no `.dmg`, no autoupdate. `make check` is a local pre-commit gate. Public distribution (signing, notarization, DMG, autoupdate, CI matrix) is one self-contained later body of work; the architecture doesn't need to anticipate it now.
19. **CLI install via in-app menu item.** `Chop > Install Command Line Tool…` symlinks the embedded `chop` shim from `Chop.app/Contents/MacOS/chop` to `/usr/local/bin/chop` (with an authorization prompt). No Homebrew cask in v1.
20. **OS-standard About panel.** `NSApp.orderFrontStandardAboutPanel(_:)` populated from `Info.plist`. No custom NSPanel.
21. **Minimal NSToolbar stub in Phase 8.** A small standard above-the-canvas toolbar (Open, Save, tool buttons, view-mode controls). Expansion is post-v1.
22. **Future File → New (post-v1).** v1 ships without one (§15.14). When added, will use either a New-Document sheet asking for width × height + background color (Photoshop / Pixelmator pattern) or a New-from-Clipboard variant that adopts the clipboard image's dimensions. Both candidate patterns are endorsed; concrete trigger TBD.
23. **Never invoke `git` from the agent.** The Claude Code harness blocks `git` for the assistant, so even attempting `git status` / `git log` / `git diff` will fail. Don't add Make targets, hooks, or scripts that the agent would call which themselves shell out to git. The human maintainer owns all version-control operations.

### Open questions (to resolve as we iterate)

*All initial open questions have been resolved into decisions §15.16 through §15.22 above. New questions will land here as they surface during implementation.*

---

## 16. Sources to consult during implementation

- AppKit documentation — Apple
- NSDocument programming guide — Apple
- NSUndoManager + responder-chain undo — Apple
- ImageIO Programming Guide & UTType reference — Apple
- ColorSync overview & EDR rendering on `CAMetalLayer` — Apple
- MetalKit `MTKView` & sampler-state docs — Apple
- swift-argument-parser — Apple
- Swift Testing — Apple
- swift-format — Apple
- Pixelmator-class image editor architecture references — public talks / WWDC sessions
