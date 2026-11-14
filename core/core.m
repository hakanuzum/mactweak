// libmactweak.dylib: the core, injected into every app with DYLD_INSERT_LIBRARIES.
//
// It links no frameworks (only libobjc and libSystem). Processes without AppKit,
// such as command line tools, load it and it does nothing there.
//
// This file: settings state, refreshing open windows, and setup. The hooks live
// in modules: corners.m (corner radius), titlebar.m (title bar), buttons.m
// (traffic light themes).

#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <notify.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "internal.h"

#ifndef MT_BUILD
#define MT_BUILD 0
#endif

// ---------------------------------------------------------------------------
// Hooking

// If the method is inherited, the override is added to this class so the
// superclass (and sibling classes) keep their behaviour.
IMP mt_hook(Class cls, const char *selector, id block) {
    if (!cls) return NULL;
    SEL s = SEL_(selector);
    Method m = class_getInstanceMethod(cls, s);
    if (!m) return NULL;
    IMP replacement = imp_implementationWithBlock(block);
    if (class_addMethod(cls, s, replacement, method_getTypeEncoding(m))) return method_getImplementation(m);
    return method_setImplementation(m, replacement);
}

// ---------------------------------------------------------------------------
// Settings state

static int g_settings_token = -1, g_app_token = -1, g_border_token = -1, g_outline_token = -1, g_alive_token = -1,
           g_listen_token = -1;
static uint64_t g_settings = 0, g_app = 0, g_border = 0, g_outline = 0;
static bool g_inert = false;  // never touch this process (not an app, or a system UI process)
static dispatch_once_t g_ready_once;

static void refresh_windows(void);

static void read_state(void) {
    uint64_t s = 0, a = 0, b = 0, o = 0;
    if (g_settings_token >= 0) notify_get_state(g_settings_token, &s);
    if (g_app_token >= 0) notify_get_state(g_app_token, &a);
    if (g_border_token >= 0) notify_get_state(g_border_token, &b);
    if (g_outline_token >= 0) notify_get_state(g_outline_token, &o);
    g_settings = ((s & 0xFF) == MT_MAGIC) ? s : 0;  // no agent: everything stays macOS default
    g_app = a;
    g_border = g_settings ? b : 0;
    g_outline = (g_settings && (o >> 56) == MT_OUTLINE_MAGIC) ? o : 0;
}

// MACTWEAK_NOTIFY_SUFFIX gives a process its own set of notify names, so tests
// can drive the core without touching the settings every other app reads.
static void notify_name(char *buf, size_t size, const char *base, const char *tail) {
    const char *suffix = getenv("MACTWEAK_NOTIFY_SUFFIX");
    snprintf(buf, size, "%s%s%s", base, tail ? tail : "", suffix ? suffix : "");
}

// System processes we never touch (login window, password and Touch ID prompts).
static const char *const kNeverTouch[] = {
    "com.apple.loginwindow", "com.apple.SecurityAgent", "com.apple.LocalAuthentication.UIAgent",
    "com.apple.coreautha", "com.apple.ScreenSaver.Engine", "com.apple.WindowManager",
    "com.apple.dock", NULL,
};

// Runs once, when the first window is built (Foundation is ready by then).
static void prepare_state(void) {
    dispatch_once(&g_ready_once, ^{
        id bundle = MSG(CLASS("NSBundle"), "mainBundle");
        const char *path = MSG_CSTR(MSG(bundle, "bundlePath"));
        const char *bundle_id = MSG_CSTR(MSG(bundle, "bundleIdentifier"));
        size_t n = path ? strlen(path) : 0;
        if (!bundle_id || n < 4 || strcmp(path + n - 4, ".app") != 0) g_inert = true;
        for (int i = 0; bundle_id && kNeverTouch[i]; i++)
            if (strcmp(bundle_id, kNeverTouch[i]) == 0) g_inert = true;

        char name[512];
        notify_name(name, sizeof name, MT_N_SETTINGS, NULL);
        notify_register_check(name, &g_settings_token);
        notify_name(name, sizeof name, MT_N_BORDER, NULL);
        notify_register_check(name, &g_border_token);
        notify_name(name, sizeof name, MT_N_OUTLINE, NULL);
        notify_register_check(name, &g_outline_token);
        if (bundle_id) {
            notify_name(name, sizeof name, MT_N_APP_PREFIX, bundle_id);
            notify_register_check(name, &g_app_token);
        }
        char alive[96];
        snprintf(alive, sizeof alive, "%s%d", MT_N_ALIVE_PREFIX, getpid());
        if (notify_register_check(alive, &g_alive_token) == NOTIFY_STATUS_OK)
            notify_set_state(g_alive_token, (uint64_t)(g_inert ? 2 : 1) | ((uint64_t)MT_BUILD << 8));
        read_state();
        notify_name(name, sizeof name, MT_N_SETTINGS, NULL);
        if (!g_inert)
            notify_register_dispatch(name, &g_listen_token, dispatch_get_main_queue(), ^(int t) {
                (void)t;
                read_state();
                if (getenv("MACTWEAK_LOG"))
                    fprintf(stderr, "[mactweak] settings changed: global=0x%llx app=0x%llx\n", g_settings, g_app);
                refresh_windows();
            });
    });
}

bool mt_enabled(void) {
    prepare_state();
    return !g_inert && (g_settings & MT_F_ENABLED) && !(g_app & MT_A_EXCLUDED);
}

bool mt_target_radius(double *top, double *bottom) {
    if (!mt_enabled()) return false;
    if (g_app & MT_A_CUSTOM_RADIUS) {
        *top = mt_top_radius(g_app);
        *bottom = mt_bottom_radius(g_app);
        return true;
    }
    if (!(g_settings & MT_F_RADIUS)) return false;
    *top = mt_top_radius(g_settings);
    *bottom = mt_bottom_radius(g_settings);
    return true;
}

bool mt_flag(uint64_t bit) { return mt_enabled() && (g_settings & bit); }

uint64_t mt_settings(void) { return g_settings; }

uint64_t mt_border(void) { return mt_enabled() ? g_border : 0; }

uint64_t mt_outline(void) { return mt_enabled() ? g_outline : 0; }

// ---------------------------------------------------------------------------
// Redraw open windows with the new settings

static void refresh_windows(void) {
    id app = MSG(CLASS("NSApplication"), "sharedApplication");
    id windows = MSG(app, "windows");
    long n = MSG_LONG(windows, "count");
    for (long i = 0; i < n; i++) {
        id w = ((id(*)(id, SEL, unsigned long))objc_msgSend)(windows, SEL_("objectAtIndex:"), (unsigned long)i);
        id frame = MSG(MSG(w, "contentView"), "superview");
        if (RESPONDS(w, "_cornerMaskChanged")) MSG_VOID(w, "_cornerMaskChanged");
        if (RESPONDS(frame, "windowCornerMaskChanged")) MSG_VOID(frame, "windowCornerMaskChanged");
        if (RESPONDS(frame, "_updateCornerInsets")) MSG_VOID(frame, "_updateCornerInsets");
        MSG_SET_BOOL(frame, "setNeedsDisplay:", YES);
        for (unsigned long b = 0; b < 3; b++) {
            id button = ((id(*)(id, SEL, unsigned long))objc_msgSend)(w, SEL_("standardWindowButton:"), b);
            // Only ask for a redraw. -update recomputes the button's visibility,
            // which hides the buttons in Chromium windows (Helium, Chrome) that
            // manage it themselves.
            MSG_SET_BOOL(button, "setNeedsDisplay:", YES);
            MSG_VOID(MSG(button, "layer"), "setNeedsDisplay");
        }
        MSG_VOID(w, "invalidateShadow");
        mt_border_update(w);
    }
}

// ---------------------------------------------------------------------------
// Setup

static bool g_installed = false;

static void install(void) {
    if (g_installed || !objc_getClass("NSThemeFrame")) return;
    g_installed = true;
    mt_corners_install();
    mt_titlebar_install();
    mt_buttons_install();
    mt_border_install();
    // Loaded into an app that is already running: update its open windows now.
    // Read the NSApp global instead of calling +sharedApplication: creating the
    // application object this early would instantiate plain NSApplication before
    // apps with their own subclass (SwiftUI, Chrome, Electron) do, and crash them.
    void **app = (void **)dlsym(RTLD_DEFAULT, "NSApp");
    if (app && *app && MSG_BOOL((__bridge id)*app, "isRunning"))
        dispatch_async(dispatch_get_main_queue(), ^{
            if (mt_enabled()) refresh_windows();
        });
    if (getenv("MACTWEAK_LOG")) fprintf(stderr, "[mactweak] hooks installed (pid %d)\n", getpid());
}

static bool appkit_loaded(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "/AppKit.framework/")) return true;
    }
    return false;
}

static void image_added(const struct mach_header *mh, intptr_t slide) {
    (void)slide;
    if (g_installed) return;
    Dl_info info;
    if (dladdr(mh, &info) && info.dli_fname && strstr(info.dli_fname, "/AppKit.framework/"))
        dispatch_async(dispatch_get_main_queue(), ^{ install(); });  // outside the dyld lock
}

__attribute__((constructor)) static void mt_start(void) {
    if (getenv("MACTWEAK_DISABLE")) return;  // escape hatch for a single process
    if (appkit_loaded())
        install();
    else
        _dyld_register_func_for_add_image(image_added);  // apps that load AppKit later (Java)
}
