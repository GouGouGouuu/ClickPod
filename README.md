# ClickPod

**A thousand ideas. In your pocket.**

A native Mac app that puts your local Codex threads inside a real, Blender-built 3D iPod. Spin the click wheel, browse the monochrome menus, and rediscover your work.

[简体中文](README.zh-CN.md) · [Download for Mac](https://github.com/GouGouGouuu/ClickPod/releases/latest)

![ClickPod — a 3D iPod for your Codex library](Preview.png)

## What it does

- Renders an editable Blender model in real time, with a white enclosure, metal back, LCD and click wheel.
- Recreates classic list navigation: circular wheel gestures, center selection, MENU back, and click sounds.
- Browses all threads stored in your local Codex database, including archived threads and agent subtasks.
- Includes search, pinned and archived views, recent threads, folder groups, and scrollable summaries.
- Refreshes every 12 seconds. Opens a selected thread in Codex via a deep link.
- Supports mouse, trackpad, keyboard navigation, and dragging the enclosure to rotate it.

## Download and requirements

Download `ClickPod-v1.0.0-macOS-arm64.zip` from [Releases](https://github.com/GouGouGouuu/ClickPod/releases/latest), unzip it, and open `ClickPod.app`. You may move it to Applications.

- **Apple Silicon Mac (M-series).** This release is not an Intel/universal build.
- Deployment target: **macOS 14 or later**. Tested on macOS 26; other supported deployment versions have not been tested on hardware.
- Codex must have a local thread database on that Mac. No Blender installation or API key is needed to run ClickPod.
- The download is ad-hoc signed, **not Apple-notarized**. macOS may block it on first launch. Building from source is also available below.

**The app interface is primarily Simplified Chinese, with English branding. These docs are bilingual; this version does not include an in-app language switch.**

## Controls

- Draw clockwise/counterclockwise around the gray wheel to move through a list. Mouse/trackpad scrolling also works.
- Press the center button to enter; press MENU to go back. Press center again in a thread's detail view to open it in Codex.
- Click the device to focus it, then use ↑ / ↓, Return / Space, and Escape / ←.
- Drag the white enclosure to rotate. The Rotate toolbar mode lets wheel-area drags rotate too; Front resets the view.
- Search matches thread titles and folder names; press Return to show results on the iPod.
- ⌘H: home menu. ⌘R: refresh. ⌘0: front view. Click sounds can be disabled in Settings.

## Languages and implementation

- **Swift** — the macOS app, menu state, LCD drawing, input handling, and generated app icon.
- **SwiftUI + AppKit** — native window, search field, toolbar and accessibility.
- **SceneKit / Metal** — real-time rendering of the exported Blender mesh.
- **Python / Blender `bpy`** — reproducible modeling, bevels, normals, materials and mesh export.
- **Shell** — local build, ad-hoc code signing and release packaging.
- **SQLite** — read-only access to the local Codex thread index.

No web runtime, third-party Swift packages, server, or account keys are required.

## Data scope

ClickPod opens the highest numbered `~/.codex/state_*.sqlite` in read-only mode. `CODEX_HOME` can select another data directory. It does not read credentials, modify the database, or send thread contents to a server.

The library contains **only threads stored on the current Mac**. Remote/cloud-only threads and ChatGPT conversations are not automatically available. Moving ClickPod to another Mac does not move your threads.

Folder groups use the last component of each working directory; equal folder names are grouped together. These groups are not Codex's formal projects. Details show saved metadata and a summary, falling back to the first user message. Execution status is not inferred from modification time.

This release uses Codex's internal database schema, not a stable public API. A future schema change may require an app update; read failures are shown in the UI.

## Build from source

With Xcode Command Line Tools installed, run from the repository root:

```sh
bash build.sh
```

The result is `ClickPod.app`. The build targets arm64/macOS 14 and uses system frameworks. Pre-generated model assets are included, so Blender is optional unless you want to change the model.

To regenerate the model, open an empty Blender scene and run in the Python Console:

```python
import runpy
runpy.run_path('/absolute/path/ClickPod/Source/build_model.py')
```

The script replaces the current scene and writes `Assets/iPod.blend` and `Assets/ipod-mesh.json`. Rebuild the app afterward. The physical enclosure is modeled in Blender; the live LCD and button labels are drawn by the app.

## Package and validate

```sh
bash package.sh
./ClickPod.app/Contents/MacOS/ClickPod --self-test
CODEX_HOME=/tmp/clickpod-nonexistent ./ClickPod.app/Contents/MacOS/ClickPod --self-test-error
```

The first self-test requires a readable Codex database. It checks navigation, list bounds, details, folder grouping, archives and empty search results. The second verifies missing-library handling. See [VALIDATION.md](VALIDATION.md) for the checked environment and limits.

## Repository layout

- `Source/`: Swift app, icon generator and Blender Python generator.
- `Assets/`: editable `.blend`, exported mesh and app icon.
- `build.sh`, `package.sh`: build and release scripts.
- `README.zh-CN.md`: Chinese documentation.
- Release downloads contain the app; generated app bundles are not tracked in Git.

An independent iPod-inspired project. Not affiliated with or endorsed by Apple or OpenAI. Product names belong to their respective owners.
