# Development notes

## Parts

| Folder | Output | Role |
|---|---|---|
| `core/` | `libmactweak.dylib` | Loaded into every process through `DYLD_INSERT_LIBRARIES`. Links only libobjc and libSystem, so processes without AppKit (command-line tools) load it and it does nothing. AppKit classes and methods are reached by name through the Objective-C runtime. |
| `agent/` | `mactweak-agent` | User LaunchAgent (`dev.hakanuzum.mactweak.agent`). Writes preferences into notify state and keeps it alive, copies the core to `~/Library/Application Support/MacTweak` (atomic rename, so running apps keep their mapped copy), sets `DYLD_INSERT_LIBRARIES` with `launchctl setenv`, and watches crash reports. Leaves the environment alone when SIP or AMFI is on. |
| `app/` | `MacTweak.app` | SwiftUI settings window. |
| `icon/` | `AppIcon.icns` | `icon/main.swift` draws the icon as vector art (plate, switch, screws, Fluent Emoji hand). A local `icon/private/icon.png` replaces it in local builds only (never in git, never in a DMG). |
| `tools/` | | `pack_button_themes.swift` renders the theme artwork to PNG and embeds it in the core; `aurorae_buttons.py` splits KDE Aurorae SVGs per state. |

Core modules: `corners.m` (corner radius), `titlebar.m` (title bar metrics and traffic-light placement), `buttons.m` (button themes), `border.m` (border, background fading, shadow and the window server's outline).

### Adding a module

1. Add the file under `core/` and to the core's file list in `build.sh`.
2. Declare `mt_<name>_install` in `core/internal.h` and call it from `install()` in `core/core.m`.
3. Add the state bits to `core/shared.h` (or a new notify name if they do not fit).
4. Write the preference into the state in `agent/agent.m`.
5. Add the pane in `app/Panes.swift` and the keys in `app/Model.swift`.

## How settings reach apps

Sandboxed apps cannot read another app's preferences or files, but they can read Darwin notify state (checked in TextEdit). The agent writes 64-bit states:

- `dev.hakanuzum.mactweak.settings`: global settings
- `dev.hakanuzum.mactweak.border`: border, fading, shadow on/off
- `dev.hakanuzum.mactweak.outline`: window server outline and shadow, as percentages of the macOS values
- `dev.hakanuzum.mactweak.app.<bundle id>`: per-app rules

The bit layouts are in `core/shared.h`. Notify state only lives while some process holds a registration, which is why the agent keeps running. Without the agent, the core changes nothing.

When a setting changes, the app posts `.reload`; the agent rewrites the states and posts `.settings`; the core redraws the corner mask, buttons and border of open windows. Only legacy apps' title bar metrics need a relaunch.

Each process that loads the core sets `dev.hakanuzum.mactweak.alive.<pid>`: bits 0–7 are 1 (active) or 2 (inert), bits 8–63 the core's build stamp. The Status page compares the stamp with the app's own to spot apps still running an older core.

## Hooks (measured on macOS 27.0.1, checked on 27.2.1)

- `-[NSThemeFrame _getCachedDefaultWindowCornerRadius]` and `_getCachedWindowCornerRadii`: the corner mask (`NSCGSWindowCornerMask`) is built from these. Default 16 pt.
- `+[NSThemeFrame/NSTitledFrame _titlebarHeight:hasSolariumAppearance:]` and related metrics: apps built with an SDK older than 26 get `NO` (28 pt title bar); the setting passes `YES` (32 pt). Old or new is read from the main executable's `LC_BUILD_VERSION`.
- `-[NSThemeFrame _collapseButtonOrigin]` and `_zoomButtonOrigin`: button spacing (20 pt in legacy apps, 23 pt in new ones), plus the user's spacing.
- `-[NSThemeFrame _shouldCenterTrafficLights]`: indents (9 → 20 pt) and centers the buttons. Not applied to windows with a toolbar.
- `-[_NSThemeWidgetCell drawWithFrame:inView:]`: button themes. `buttonID` 25 close, 26 minimize, 27 zoom.
- `-[NSWindow becomeKeyWindow]`, `resignKeyWindow`, `orderWindow:relativeTo:`: border updates.
- `-[NSWindow shadowParameters]`: the dictionary AppKit sends to the window server with the shadow. `com.apple.WindowShadowRimDensity*` is the dark outline, `InnerRimDensity*` the light line inside it (Increase Contrast), `Density*`, `Radius*` and `VerticalOffset*` the shadow. `-_setShadowParameters` resends it.

Windows without a title bar (the input-language bubble, `TUINSCursorUIController`, and the like) are left alone.

### Lessons

- **The core's constructor runs before the app has set itself up.** Do not message AppKit classes there; the `retain` ARC inserts is a message too. It runs `+initialize` early and SwiftUI, Chromium and Electron apps crash. That is why `CLASS()` is a macro, not a function.
- `-[_NSThemeWidget update]` hides the traffic lights in Chromium windows. Redraw with `setNeedsDisplay` only.
- `+[NSNumber new]` returns nil. Use `numberWithBool:`.
- A view added on top of the theme frame changes how AppKit lays out SwiftUI toolbars (the tab capsule of Settings windows grows). The border is the frame layer's own `borderWidth`/`borderColor`, which CALayer draws above its sublayers.
- The window server draws its outline over the window's edge, so a border is only fully visible with the inner line off. Window captures (`screencapture -l`) do not show the outline; full-screen captures do.
- `titlebarSeparatorStyle` has no visible effect on macOS 27; separators come from `NSScrollPocket`.

## Testing

Never test against the live notify names: every app on the Mac reads them. Give the test process its own set:

```bash
MACTWEAK_NOTIFY_SUFFIX=.test MACTWEAK_LOG=1 \
DYLD_INSERT_LIBRARIES=$PWD/build/MacTweak.app/Contents/Frameworks/libmactweak.dylib \
/System/Applications/TextEdit.app/Contents/MacOS/TextEdit
```

and set `dev.hakanuzum.mactweak.settings.test` (and `.border.test`, `.outline.test`) with any tool that calls `notify_set_state` and keeps the registration open. `MACTWEAK_DISABLE=1` turns the core off in a process.

Before installing a new core, try it in a SwiftUI app, System Events and TextEdit this way: a crash in the constructor takes down every app opened afterwards.

## Release

```bash
./build.sh --dmg   # dist/MacTweak-<version>.dmg and .sha256, always with the vector icon
```

The version is `CFBundleShortVersionString` in `app/Info.plist`; `CFBundleVersion` and `MTCoreBuild` come from the build time.
