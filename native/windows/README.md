# Windows native move / resize gate

Godot 4.5.1 runs a full `Main::iteration()` from Win32 timer 1 while its window
is in the system move/resize modal loop. `WM_WINDOWPOSCHANGED` also synchronously
rebuilds the outer viewport, and `WM_PAINT` requests another renderer frame.
Those operations share the window-message thread with native dragging.

This small, Windows x64 GDExtension removes that work **only while an actual
native move/resize gesture is active**. It does not replace the title bar,
implement a custom drag loop, change system settings, or inspect another app.

- Enumerate only the current thread's windows, requiring exactly one ownerless
  top-level HWND with our process/thread identity and Godot `Engine` window class.
  This avoids relying on a DisplayServer singleton before its registration.
- Skip editor/headless launch arguments before looking for windows; check
  `Engine.is_editor_hint()` as well. Skip ambiguous/no-window configurations and
  engine versions other than 4.5.1.
- Forward `WM_ENTERSIZEMOVE` first, preserving Godot's input-release and moving
  bookkeeping; cancel only redraw timer 1 and swallow its queued messages.
- Defer `WM_WINDOWPOSCHANGED` notifications during the gesture. The OS continues
  moving the real window. Keep hit testing, constraints, focus, activation,
  system commands, DPI and close processing in the original window procedure.
- Send ordinary key/character messages directly to Windows during the gesture,
  preventing a queued Enter key from playing a tile after release. System key
  messages remain in the normal path for Alt+F4, Alt+Tab and system commands.
- Validate `WM_PAINT` with `BeginPaint` / `EndPaint`, suppress background erasing,
  and retain the last presented frame. No screenshots, GPU readbacks or GDI
  image copies are performed. How newly exposed margins look while resizing
  remains a Windows/graphics-driver behavior; a live redraw is requested on exit.
- Forward `WM_EXITSIZEMOVE`, then synchronously deliver one geometry notification
  so Godot reads the actual final client rectangle and window state.
- Remove the subclass on native destruction and extension shutdown.

The game does not advance/render inside this native modal loop. This is an
intentional short pause while arranging the window. This gate prevents the
identified engine callbacks; source review and compilation alone do not prove
that dragging is smooth on a particular graphics driver.

## Build

Run `tools/build_native.ps1`; use `-Force` to rebuild. It checks source/header and
script timestamps and does not rebuild an up-to-date DLL. The default toolchain
is Visual Studio 2026 Community with the x64 MSVC tools and Windows SDK
10.0.26100.0. `-VisualStudio` and `-SdkVersion` allow another installed toolchain;
the script also tries Microsoft's `vswhere` if the default location is absent.

The extension uses the vendored official MIT-licensed GDExtension C interface,
not the full godot-cpp library. `/MT` statically links the C++ runtime. The DLL
otherwise uses Windows' `user32`, `comctl32` and `shell32` libraries.

Output: `native/windows/bin/motion_gate.windows.x86_64.dll`. Object/import files
are isolated in `native/windows/build/`. Both are rebuildable outputs; retain
the `.cpp`, `.gdextension`, vendored header/license and build script in Git.
The Windows export must include the DLL resolved by `motion_gate.gdextension`.
Other-platform exports should exclude this Windows-only extension descriptor.

## Evidence

When launched with `-- --qa --capture-dir <filesystem-directory>`, the extension
writes `native-motion.json` on installation, after completed native gestures,
and on shutdown. It records entries/exits, skipped rectangle/timer/paint events,
one-time final synchronizations and monotonic gesture durations. A queued timer
count of zero is normal when `KillTimer` cancelled it before one was queued.
No QA arguments means no diagnostic files. No player preference or match file
is read or written by this extension.

Counters describe received messages, not perceived smoothness or synthetic
performance results. `entries == 0` does not count as a native drag test.

`headless_probe.gd` is a minimal loader check: run Godot with `--headless --path
<project> --script res://native/windows/headless_probe.gd -- --qa --capture-dir
<directory>`. It quits without constructing the application scene. Expect
`NATIVE_HEADLESS_PROBE: initialized` and a skipped headless status, with no engine
errors. Exclude this development-only probe from exported packages.

Upstream mechanism: Godot `4.5.1-stable`
[`display_server_windows.cpp`](https://github.com/godotengine/godot/blob/4.5.1-stable/platform/windows/display_server_windows.cpp),
[`display_server_windows.h`](https://github.com/godotengine/godot/blob/4.5.1-stable/platform/windows/display_server_windows.h).
