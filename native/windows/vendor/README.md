# Vendored Godot interface

The unmodified `gdextension_interface.h` and `GODOT-LICENSE.txt` come from the
official Godot **4.5.1-stable** tag, under the MIT license:

- <https://github.com/godotengine/godot/blob/4.5.1-stable/core/extension/gdextension_interface.h>
- <https://github.com/godotengine/godot/blob/4.5.1-stable/LICENSE.txt>

No Godot C++ implementation or godot-cpp binding library is compiled into this
extension. The interface is used only to identify the real game window and skip
editor/headless/unreviewed engine configurations.

SHA-256:

- `gdextension_interface.h`: `a40ac4fca0f526910bd0e6afc6da6c169f50801c84d4e29c4ce2891cadc7b550`
- `GODOT-LICENSE.txt`: `b0435e3b3e4e55238f05f4b306f30524a1b2e20147810d436eaa554fa6855c80`
