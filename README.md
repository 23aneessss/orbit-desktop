# Orbit for macOS

Orbit is a local-first personal operating system for habits, connected ideas, visual workflows, tasks, and relationships. This repository is the native macOS recreation of Orbit 1.0, built with SwiftUI and SwiftData.

The complete source-product specification is in [CAHIER_DES_CHARGES.md](CAHIER_DES_CHARGES.md). [PRODUCT.md](PRODUCT.md) captures the durable product principles for the native port.

## Status

The native product foundation and its core feature set are implemented and build successfully:

- Native macOS window and persistent collapsible sidebar
- Warm neutral Orbit visual foundation and accent system
- Local SwiftData store with idempotent sample data
- Home dashboard with live habit, idea, relationship, follow-up, and activity data
- Habit list, contribution heatmaps, weekly progress, and today toggles
- Searchable idea browser with tags, pinning, deletion, and a distraction-free 700 ms autosaving editor
- `⌘K` command palette for navigation, creation, habit logging, and content lookup
- Native idea canvas with a dot grid, pan, zoom, draggable nodes, persisted positions, accessible link ports, floating border-to-border Bézier edges, auto-tiling, deletion, and overlap merge reconciliation
- Persistent task lists, hierarchical steps, recursive completion roll-up, directed workflow links, composite drill-down, freehand ink, and sticky notes
- Relationship CRM with contact detail, favorites, interaction history, and follow-up states
- Profile, light/dark/system appearance, custom accent colors, complete JSON export, and erase-all-data controls
- Light and dark system appearance support

## Why React Flow is not required

React Flow is a React component and cannot be embedded directly in a native SwiftUI view. Orbit replaces it with a native scene architecture:

1. Nodes and annotation points are stored in world-space coordinates.
2. A viewport transform applies shared pan and zoom to the scene.
3. Interactive nodes remain real SwiftUI views, preserving text rendering, focus, controls, and accessibility.
4. Non-interactive edges, the dot grid, and future pen strokes use SwiftUI `Canvas` for efficient immediate-mode drawing.
5. A small geometry layer computes floating edge attachment points at node borders.
6. If very large boards outgrow SwiftUI rendering, the drawing layer can move to an `NSView` without changing the persisted model or product UI.

This is the native equivalent of the capabilities Orbit uses from React Flow. It also gives the app better macOS keyboard, pointer, accessibility, and persistence integration.

## Open and run

The checked-in Xcode project is generated from `project.yml` with XcodeGen.

```sh
open Orbit.xcodeproj
```

Select the `Orbit` scheme and run on **My Mac**.

To regenerate and verify from the command line:

```sh
xcodegen generate
xcodebuild -project Orbit.xcodeproj -scheme Orbit -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Requirements:

- macOS 14 Sonoma or later
- Xcode 15.0 or later
- XcodeGen when regenerating the project

## Architecture

```text
Orbit/
├── App/          App entry point, model container, menu commands
├── Design/       Theme tokens and shared surface styling
├── Models/       SwiftData entities
├── Services/     Local seed and future import/export services
├── Utilities/    Date and business-logic helpers
└── Views/        App shell and feature screens
```

All application data stays in SwiftData's local SQLite-backed store. UI-only preferences such as sidebar collapse remain in `UserDefaults`. There are no network dependencies.

## Parity roadmap

### Phase 1: foundation and risk proof

- [x] Native project and app shell
- [x] Product/design foundations
- [x] SwiftData proof
- [x] Home and Habits vertical slice
- [x] Native canvas pan, zoom, drag, persistence, and edges
- [x] Canvas connection ports, selection, deletion, auto-tiling, and merge flow
- [ ] Canvas keyboard navigation and large-board performance tests

### Phase 2: Ideas

- [x] Searchable idea browser, tags, pinning, and deletion
- [x] Distraction-free editor with 700 ms autosave
- [x] Canvas double-click creation at pointer position
- [x] Link normalization and duplicate protection
- [x] Overlap-based idea merge with link reconciliation

### Phase 3: Tasks and workflows

- [x] Task list
- [x] Spatial task board with persisted positions, auto-tiling, task states, and annotations
- [x] Hierarchical steps and memoized completion roll-up
- [x] Directed workflow links
- [x] Composite workflow drill-down
- [x] Pen strokes, sticky notes, selection, undo, and deletion
- [ ] Shared board viewport engine extracted from the idea canvas

### Phase 4: People and daily operating loop

- [x] Contact browser and detail views
- [x] Interaction timeline and follow-up states
- [x] Complete Home follow-up and recent-idea panels
- [x] Full command palette actions and habit logging

### Phase 5: ownership and parity hardening

- [x] Theme and accent settings
- [x] Complete JSON export and erase-all-data flow
- [ ] JSON import with conflict handling
- [ ] Empty, error, and rollback states
- [ ] VoiceOver, keyboard, focus, reduced-motion, and contrast audit
- [ ] Performance testing with large datasets and canvases
- [ ] Visual comparison pass against every source screen

## Definition of exact recreation

Exact recreation is achievable at the product level: the same information architecture, data behavior, canvas workflows, visual hierarchy, and keyboard-first operating model. Some implementation details should intentionally be native equivalents, such as SF Symbols instead of Lucide icons, SwiftData instead of Drizzle, macOS menus and file panels instead of browser dialogs, and the custom scene layer instead of React Flow.
