// MacTweak: constants shared by the injected core, the agent and the settings app.
//
// Settings reach apps through Darwin notify 64-bit state values. Sandboxed apps
// cannot read other domains' preferences or arbitrary files, but they can read
// notify state. A notify state only lives while some process keeps a
// registration open, so mactweak-agent stays running and holds them.
#ifndef MT_SHARED_H
#define MT_SHARED_H

#include <stdint.h>

#define MT_DOMAIN "dev.hakanuzum.mactweak"

// Global settings state. Written by the agent, read by the core in every app.
#define MT_N_SETTINGS MT_DOMAIN ".settings"
// Per-app state: MT_N_APP_PREFIX + bundle identifier.
#define MT_N_APP_PREFIX MT_DOMAIN ".app."
// Set by the core once loaded into a process: MT_N_ALIVE_PREFIX + pid.
// State: bits 0-7 = 1 active / 2 inert, bits 8-63 = the core's build stamp.
#define MT_N_ALIVE_PREFIX MT_DOMAIN ".alive."
// Posted by the settings app when preferences change; the agent re-reads them.
#define MT_N_RELOAD MT_DOMAIN ".reload"
// Border, window opacity and shadow settings (see the layout below).
#define MT_N_BORDER MT_DOMAIN ".border"

// --- Global state (uint64) ---
// bits 0-7   : magic byte; missing means the agent is not running and the core touches nothing
// bit 8      : enabled
// bit 9      : override corner radius (off: macOS default)
// bits 16-23 : top corner radius x2 (0-127.5 pt)
// bits 24-31 : bottom corner radius x2
// bit 32     : legacy apps: macOS 27 traffic light spacing
// bit 33     : legacy apps: taller title bar
// bit 34     : indent and vertically center traffic lights
// bit 36     : keep buttons colored in inactive windows
// bits 40-47 : button theme (0 = system)
// bits 48-55 : extra traffic light spacing in pt, stored +64 (64 = system spacing)
#define MT_MAGIC 0x4BULL
#define MT_F_ENABLED (1ULL << 8)
#define MT_F_RADIUS (1ULL << 9)
#define MT_F_LEGACY_SPACING (1ULL << 32)
#define MT_F_LEGACY_TITLEBAR (1ULL << 33)
#define MT_F_INDENT_LIGHTS (1ULL << 34)
#define MT_F_INACTIVE_COLOR (1ULL << 36)

// --- Border state (uint64, MT_N_BORDER) ---
// bits 0-31  : border color RGBA, 8 bits each (R in bits 0-7)
// bits 32-39 : border width x4 (0-63.75 pt)
// bit 40     : border on
// bit 41     : only on the active (key) window
// bit 42     : remove window shadows
// bits 48-55 : opacity of inactive windows in percent (0 or 100 = unchanged)
#define MT_B_ENABLED (1ULL << 40)
#define MT_B_ACTIVE_ONLY (1ULL << 41)
#define MT_B_NO_SHADOW (1ULL << 42)

static inline int mt_button_spacing(uint64_t s) { return (int)((s >> 48) & 0xFF) - 64; }
static inline double mt_border_width(uint64_t b) { return (double)((b >> 32) & 0xFF) / 4.0; }
static inline int mt_inactive_opacity(uint64_t b) { return (int)((b >> 48) & 0xFF); }

// --- Per-app state (uint64) ---
// bit 0      : excluded (do not touch this app at all)
// bit 1      : custom radius (bits 16-31 laid out like the global state)
#define MT_A_EXCLUDED (1ULL << 0)
#define MT_A_CUSTOM_RADIUS (1ULL << 1)

// Button themes. The settings app lists them in this order.
enum {
    MT_THEME_SYSTEM = 0,
    MT_THEME_CLASSIC = 1,
    MT_THEME_SQUARE = 2,
    MT_THEME_RING = 3,
    MT_THEME_GRAPHITE = 4,
    MT_THEME_DOT = 5,
    MT_THEME_PASTEL = 6,
    MT_THEME_AQUA = 7,      // glossy gel
    MT_THEME_PLATINUM = 8,  // beveled gray boxes
    MT_THEME_BLACK = 9,
    MT_THEME_SYMBOLS = 10,  // gray, symbols always visible
    MT_THEME_CAPSULE = 11,
    MT_THEME_NEON = 12,     // dark with a glowing colored rim
    // 32 and up: image themes from open-source GTK/xfwm4 themes
    // (assets/button-themes, packed by tools/pack_button_themes.swift)
    MT_THEME_IMAGE_BASE = 32,
};

static inline uint64_t mt_encode_radius(double top, double bottom) {
    uint64_t t = (uint64_t)(top * 2 + 0.5), b = (uint64_t)(bottom * 2 + 0.5);
    if (t > 255) t = 255;
    if (b > 255) b = 255;
    return (t << 16) | (b << 24);
}
static inline double mt_top_radius(uint64_t s) { return (double)((s >> 16) & 0xFF) / 2.0; }
static inline double mt_bottom_radius(uint64_t s) { return (double)((s >> 24) & 0xFF) / 2.0; }
static inline int mt_theme(uint64_t s) { return (int)((s >> 40) & 0xFF); }

#endif
