# Chop

A simple, fast, **macOS-only** image editor. CLI: `chop`. App name: `Chop`.

Designed to feel like a native Mac app — built with AppKit, NSDocument, NSUndoManager, ImageIO, ColorSync, and Metal directly.

See `AGENTS.md` for the project's invariants and a map of where things live.

## Build

```sh
brew install xcodegen        # one-time
make build                    # build the .app
make run                      # build and launch
make test                     # run the test suite
make check                    # lint + test (pre-commit gate)
```

## License

Dual-licensed under MIT or Apache-2.0 at your option. See `LICENSE-MIT` and `LICENSE-APACHE`.
