#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <commctrl.h>
#include <shellapi.h>

#include "vendor/gdextension_interface.h"

#include <algorithm>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <string>

namespace {
// Verified against Godot 4.5.1 platform/windows/display_server_windows.h.
// Leave activation timer 2 and every unrelated message alone.
constexpr UINT_PTR GODOT_MOVE_REDRAW_TIMER = 1;
constexpr UINT_PTR SUBCLASS_ID = 0x514D4741;

struct GateState {
    HWND window = nullptr;
    bool installed = false;
    bool installed_once = false;
    bool active = false;
    bool qa = false;
    bool excluded_launch = false;
    UINT flush_message = 0;
    uint64_t entries = 0;
    uint64_t exits = 0;
    uint64_t skipped_rects = 0;
    uint64_t skipped_timers = 0;
    uint64_t skipped_paints = 0;
    uint64_t skipped_erases = 0;
    uint64_t skipped_keys = 0;
    uint64_t geometry_syncs = 0;
    uint64_t timer_kill_failures = 0;
    uint64_t last_duration_usec = 0;
    uint64_t total_duration_usec = 0;
    uint64_t max_duration_usec = 0;
    LARGE_INTEGER started{};
    LARGE_INTEGER frequency{};
    RECT final_client{};
    std::filesystem::path report_path;
    std::string status = "initializing";
} state;

GDExtensionInterfaceGetProcAddress get_proc = nullptr;
GDExtensionInterfaceStringNameNewWithLatin1Chars name_new = nullptr;
GDExtensionPtrDestructor name_destroy = nullptr;
GDExtensionInterfaceGlobalGetSingleton get_singleton = nullptr;
GDExtensionInterfaceVariantCall variant_call = nullptr;
GDExtensionInterfaceVariantDestroy variant_destroy = nullptr;
GDExtensionInterfaceGetVariantFromTypeConstructor from_type = nullptr;
GDExtensionInterfaceGetVariantToTypeConstructor to_type = nullptr;

// Godot 4.5.1's x64 Variant is 24 bytes. Oversized, suitably aligned storage
// avoids binding to C++ internals; only the public interface constructs it.
struct alignas(16) OpaqueValue { unsigned char bytes[64]{}; };

template <typename T> T api(const char *name) {
    return reinterpret_cast<T>(get_proc(name));
}

bool call_singleton(const char *singleton, const char *method,
        const GDExtensionConstVariantPtr *arguments, int count,
        OpaqueValue &result) {
    OpaqueValue object_name, method_name, object_variant;
    name_new(object_name.bytes, singleton, false);
    auto object = get_singleton(object_name.bytes);
    name_destroy(object_name.bytes);
    if (!object) return false;
    name_new(method_name.bytes, method, false);
    from_type(GDEXTENSION_VARIANT_TYPE_OBJECT)(object_variant.bytes, &object);
    GDExtensionCallError error{};
    variant_call(object_variant.bytes, method_name.bytes, arguments, count,
        result.bytes, &error);
    variant_destroy(object_variant.bytes);
    name_destroy(method_name.bytes);
    if (error.error != GDEXTENSION_CALL_OK) {
        variant_destroy(result.bytes);
        return false;
    }
    return true;
}

void parse_qa_arguments() {
    int count = 0;
    LPWSTR *arguments = CommandLineToArgvW(GetCommandLineW(), &count);
    if (!arguments) return;
    std::wstring directory;
    bool user_arguments = false;
    for (int i = 1; i < count; ++i) {
        const std::wstring argument(arguments[i]);
        if (!user_arguments && (argument == L"--headless" || argument == L"--editor" ||
                argument == L"-e" || argument == L"--project-manager" || argument == L"-p"))
            state.excluded_launch = true;
        if (!user_arguments && argument == L"--display-driver" && i + 1 < count &&
                std::wstring(arguments[i + 1]) == L"headless") state.excluded_launch = true;
        if (argument == L"--") user_arguments = true;
        if (!user_arguments) continue;
        if (std::wstring(arguments[i]) == L"--qa") state.qa = true;
        if (std::wstring(arguments[i]) == L"--capture-dir" && i + 1 < count)
            directory = arguments[++i];
    }
    LocalFree(arguments);
    // The QA launcher passes a filesystem directory. Do not misinterpret
    // Godot virtual resource paths or write anything during normal play.
    if (state.qa && !directory.empty() && directory.find(L"://") == std::wstring::npos)
        state.report_path = std::filesystem::path(directory) / L"native-motion.json";
}

void write_report() noexcept {
    if (state.report_path.empty()) return;
    try {
        std::filesystem::create_directories(state.report_path.parent_path());
        std::ofstream file(state.report_path, std::ios::binary | std::ios::trunc);
        if (!file) return;
        file << "{\n  \"schema\": 1,\n"
             << "  \"measurement\": \"native Win32 modal move/resize messages; no synthetic gesture\",\n"
             << "  \"status\": \"" << state.status << "\",\n"
             << "  \"installed\": " << (state.installed ? "true" : "false") << ",\n"
             << "  \"installed_once\": " << (state.installed_once ? "true" : "false") << ",\n"
             << "  \"interactive\": " << (state.active ? "true" : "false") << ",\n"
             << "  \"process_id\": " << GetCurrentProcessId() << ",\n"
             << "  \"entries\": " << state.entries << ",\n"
             << "  \"exits\": " << state.exits << ",\n"
             << "  \"skipped_windowposchanged\": " << state.skipped_rects << ",\n"
             << "  \"skipped_timer_1\": " << state.skipped_timers << ",\n"
             << "  \"skipped_paint\": " << state.skipped_paints << ",\n"
             << "  \"skipped_erase\": " << state.skipped_erases << ",\n"
             << "  \"skipped_keys\": " << state.skipped_keys << ",\n"
             << "  \"geometry_syncs\": " << state.geometry_syncs << ",\n"
             << "  \"timer_kill_failures\": " << state.timer_kill_failures << ",\n"
             << "  \"last_duration_usec\": " << state.last_duration_usec << ",\n"
             << "  \"total_duration_usec\": " << state.total_duration_usec << ",\n"
             << "  \"max_duration_usec\": " << state.max_duration_usec << ",\n"
             << "  \"final_client_width\": " << state.final_client.right << ",\n"
             << "  \"final_client_height\": " << state.final_client.bottom << "\n}\n";
    } catch (...) {
        // Diagnostics must never interrupt the window procedure or gameplay.
    }
}

void synchronize_geometry(HWND window) {
    if (!IsWindow(window)) return;
    RECT rect{};
    if (!GetWindowRect(window, &rect)) return;
    WINDOWPOS position{};
    position.hwnd = window;
    position.x = rect.left;
    position.y = rect.top;
    position.cx = rect.right - rect.left;
    position.cy = rect.bottom - rect.top;
    // No NOSIZE/NOMOVE: Godot rereads GetClientRect/ClientToScreen and updates
    // maximized/fullscreen state itself. Send synchronously: no pointer escapes.
    ++state.geometry_syncs;
    SendMessageW(window, WM_WINDOWPOSCHANGED, 0, reinterpret_cast<LPARAM>(&position));
    GetClientRect(window, &state.final_client);
    // Request a normal engine frame after the native modal loop has returned.
    InvalidateRect(window, nullptr, FALSE);
}

LRESULT CALLBACK window_subclass(HWND window, UINT message, WPARAM wparam,
        LPARAM lparam, UINT_PTR, DWORD_PTR) {
    if (message == state.flush_message && state.flush_message != 0) {
        if (!state.active) write_report();
        return 0;
    }
    if (message == WM_ENTERSIZEMOVE) {
        state.active = true;
        ++state.entries;
        QueryPerformanceCounter(&state.started);
        // Godot's moving flag also protects native mouse capture on activation.
        // Preserve that bookkeeping, then cancel only its redraw timer.
        const LRESULT result = DefSubclassProc(window, message, wparam, lparam);
        if (!KillTimer(window, GODOT_MOVE_REDRAW_TIMER)) ++state.timer_kill_failures;
        return result;
    }
    if (state.active) {
        if (message == WM_TIMER && wparam == GODOT_MOVE_REDRAW_TIMER) {
            // KillTimer does not remove already queued WM_TIMER messages.
            ++state.skipped_timers;
            return 0;
        }
        if (message == WM_WINDOWPOSCHANGED) {
            ++state.skipped_rects;
            // The OS has already moved/resized the HWND. Godot itself also
            // returns zero here rather than letting DefWindowProc manufacture
            // extra WM_SIZE/WM_MOVE messages. Keep only its scene state frozen.
            return 0;
        }
        if (message == WM_PAINT) {
            ++state.skipped_paints;
            PAINTSTRUCT paint{};
            BeginPaint(window, &paint);
            EndPaint(window, &paint);
            // Retain the compositor's previous frame. No GPU readback or GDI
            // drawing; newly exposed margins are owned by Windows/the driver.
            return 0;
        }
        if (message == WM_ERASEBKGND) {
            ++state.skipped_erases;
            return 1;
        }
        if (message == WM_KEYDOWN || message == WM_KEYUP || message == WM_CHAR ||
                message == WM_DEADCHAR || message == WM_UNICHAR) {
            ++state.skipped_keys;
            // Let Windows handle Enter/Escape in its modal loop, without
            // queuing a gameplay key for the first frame after release.
            // WM_SYSKEY* remains untouched for Alt+F4/Alt+Tab/system commands.
            return DefWindowProcW(window, message, wparam, lparam);
        }
    }
    if (message == WM_EXITSIZEMOVE) {
        const bool was_active = state.active;
        state.active = false;
        const LRESULT result = DefSubclassProc(window, message, wparam, lparam);
        if (was_active && IsWindow(window)) {
            ++state.exits;
            LARGE_INTEGER now{};
            QueryPerformanceCounter(&now);
            state.last_duration_usec = static_cast<uint64_t>(
                (now.QuadPart - state.started.QuadPart) * 1000000 / state.frequency.QuadPart);
            state.total_duration_usec += state.last_duration_usec;
            state.max_duration_usec = std::max(state.max_duration_usec, state.last_duration_usec);
            synchronize_geometry(window);
            if (state.flush_message) PostMessageW(window, state.flush_message, 0, 0);
        }
        return result;
    }
    if (message == WM_NCDESTROY) {
        state.active = false;
        RemoveWindowSubclass(window, window_subclass, SUBCLASS_ID);
        state.installed = false;
        state.window = nullptr;
        write_report();
        return DefSubclassProc(window, message, wparam, lparam);
    }
    // Includes WM_GETMINMAXINFO, WM_WINDOWPOSCHANGING, nonclient hit testing,
    // focus/activation, DPI/display changes, system commands and close.
    return DefSubclassProc(window, message, wparam, lparam);
}

struct WindowCandidate {
    HWND window = nullptr;
    unsigned int count = 0;
};

BOOL CALLBACK find_owned_window(HWND window, LPARAM parameter) {
    DWORD process_id = 0;
    const DWORD thread_id = GetWindowThreadProcessId(window, &process_id);
    wchar_t class_name[64]{};
    GetClassNameW(window, class_name, 64);
    if (process_id == GetCurrentProcessId() && thread_id == GetCurrentThreadId() &&
            GetAncestor(window, GA_ROOT) == window && !GetWindow(window, GW_OWNER) &&
            std::wstring(class_name) == L"Engine") {
        auto &candidate = *reinterpret_cast<WindowCandidate *>(parameter);
        candidate.window = window;
        ++candidate.count;
    }
    return TRUE;
}

void initialize(void *, GDExtensionInitializationLevel level) {
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    parse_qa_arguments();
    QueryPerformanceFrequency(&state.frequency);
    if (state.excluded_launch) {
        state.status = "skipped_editor_or_headless_arguments";
        write_report();
        return;
    }
    auto version_get = api<GDExtensionInterfaceGetGodotVersion>("get_godot_version");
    GDExtensionGodotVersion version{};
    version_get(&version);
    // This extension depends on a private Win32 timer id. Fail open on an
    // unreviewed engine version rather than interfering with another timer.
    if (version.major != 4 || version.minor != 5 || version.patch != 1) {
        state.status = "skipped_unreviewed_engine_version";
        write_report();
        return;
    }
    OpaqueValue result;
    if (!call_singleton("Engine", "is_editor_hint", nullptr, 0, result)) {
        state.status = "skipped_engine_api_unavailable";
        write_report();
        return;
    }
    GDExtensionBool editor = false;
    to_type(GDEXTENSION_VARIANT_TYPE_BOOL)(&editor, result.bytes);
    variant_destroy(result.bytes);
    if (editor) {
        state.status = "skipped_editor";
        write_report();
        return;
    }
    // DisplayServer is not exposed as an Engine singleton at this startup
    // phase. Enumerate only this thread, after the editor/headless checks.
    // Never inspect another process or guess between multiple Engine windows.
    WindowCandidate candidate;
    EnumThreadWindows(GetCurrentThreadId(), find_owned_window, reinterpret_cast<LPARAM>(&candidate));
    if (candidate.count != 1 || !IsWindow(candidate.window)) {
        state.status = "skipped_no_unique_owned_main_window";
        write_report();
        return;
    }
    HWND window = candidate.window;
    state.flush_message = RegisterWindowMessageW(L"QingyuMahjong.MotionGate.Flush.4.5.1");
    state.installed = SetWindowSubclass(window, window_subclass, SUBCLASS_ID, 0) != FALSE;
    state.installed_once = state.installed;
    state.window = state.installed ? window : nullptr;
    state.status = state.installed ? "active" : "subclass_install_failed";
    write_report();
}

void deinitialize(void *, GDExtensionInitializationLevel level) {
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    if (state.installed && IsWindow(state.window)) {
        RemoveWindowSubclass(state.window, window_subclass, SUBCLASS_ID);
        state.installed = false;
        state.window = nullptr;
        state.active = false;
    }
    write_report();
}
} // namespace

extern "C" __declspec(dllexport) GDExtensionBool motion_gate_init(
        GDExtensionInterfaceGetProcAddress address, GDExtensionClassLibraryPtr,
        GDExtensionInitialization *initialization) {
    get_proc = address;
    name_new = api<GDExtensionInterfaceStringNameNewWithLatin1Chars>("string_name_new_with_latin1_chars");
    get_singleton = api<GDExtensionInterfaceGlobalGetSingleton>("global_get_singleton");
    variant_call = api<GDExtensionInterfaceVariantCall>("variant_call");
    variant_destroy = api<GDExtensionInterfaceVariantDestroy>("variant_destroy");
    from_type = api<GDExtensionInterfaceGetVariantFromTypeConstructor>("get_variant_from_type_constructor");
    to_type = api<GDExtensionInterfaceGetVariantToTypeConstructor>("get_variant_to_type_constructor");
    auto get_destructor = api<GDExtensionInterfaceVariantGetPtrDestructor>("variant_get_ptr_destructor");
    if (!name_new || !get_singleton || !variant_call || !variant_destroy || !from_type ||
            !to_type || !get_destructor || !get_proc("get_godot_version")) return false;
    name_destroy = get_destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);
    if (!name_destroy) return false;
    initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    initialization->userdata = nullptr;
    initialization->initialize = initialize;
    initialization->deinitialize = deinitialize;
    return true;
}
