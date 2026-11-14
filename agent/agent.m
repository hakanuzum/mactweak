// mactweak-agent: MacTweak's background process (a user LaunchAgent).
//
// 1. Reads preferences (dev.hakanuzum.mactweak), writes them into notify states
//    and keeps those registrations open. The core in every app reads them.
// 2. Copies the core to ~/Library/Application Support/MacTweak and adds it to
//    the user launchd environment as DYLD_INSERT_LIBRARIES (no root needed).
// 3. Watches crash reports: an app that crashes because of the core is
//    excluded automatically and the user gets a notification.
// 4. If the session just started and Finder came up without the core, restarts
//    Finder once.

#import <Foundation/Foundation.h>
#include <fcntl.h>
#include <notify.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <string.h>
#include <unistd.h>

#include "../core/shared.h"

static NSString *const kDomain = @MT_DOMAIN;
static NSString *const kCoreName = @"libmactweak.dylib";
static int g_settings_token = -1, g_border_token = -1, g_outline_token = -1;
static NSMutableDictionary<NSString *, NSNumber *> *g_app_tokens;
static NSString *g_core_path;  // installed core
static NSDate *g_started;
static dispatch_source_t g_crash_watch, g_sigterm;  // keep ARC from releasing them

static void logf_(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void logf_(NSString *fmt, ...) {
    va_list a;
    va_start(a, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:a];
    va_end(a);
    fprintf(stderr, "%s mactweak-agent: %s\n", NSDate.date.description.UTF8String, s.UTF8String);
}

// MACTWEAK_TEST=1: leave the session alone (no environment change, no Finder restart).
static BOOL test_mode(void) { return getenv("MACTWEAK_TEST") != NULL; }

// --- preferences -----------------------------------------------------------

static id pref(NSString *key) {
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kDomain));
}
static BOOL pref_bool(NSString *key, BOOL fallback) {
    id v = pref(key);
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : fallback;
}
static double pref_double(NSString *key, double fallback) {
    id v = pref(key);
    return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : fallback;
}
static void pref_set(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)kDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
}

// Corner styles; must match the list in the settings app.
static BOOL style_radius(NSString *style, double *top, double *bottom) {
    if ([style isEqual:@"system"]) return NO;
    if ([style isEqual:@"medium"]) { *top = *bottom = 13; return YES; }
    if ([style isEqual:@"catalina"]) { *top = 5; *bottom = 0; return YES; }
    if ([style isEqual:@"square"]) { *top = *bottom = 0; return YES; }
    if ([style isEqual:@"custom"]) {
        *top = pref_double(@"customTop", 10);
        *bottom = pref_double(@"customBottom", 10);
        return YES;
    }
    *top = *bottom = 10;  // sequoia (default)
    return YES;
}

static uint64_t global_state(void) {
    uint64_t s = MT_MAGIC;
    if (pref_bool(@"enabled", YES)) s |= MT_F_ENABLED;
    double top = 0, bottom = 0;
    id style = pref(@"cornerStyle");
    if (style_radius([style isKindOfClass:NSString.class] ? style : @"sequoia", &top, &bottom))
        s |= MT_F_RADIUS | mt_encode_radius(top, bottom);
    if (pref_bool(@"indentTrafficLights", NO)) s |= MT_F_INDENT_LIGHTS;
    if (pref_bool(@"legacyTitlebarHeight", NO)) s |= MT_F_LEGACY_TITLEBAR;
    if (pref_bool(@"legacyButtonSpacing", NO)) s |= MT_F_LEGACY_SPACING;
    if (pref_bool(@"inactiveButtonColor", NO)) s |= MT_F_INACTIVE_COLOR;
    uint64_t theme = (uint64_t)pref_double(@"buttonTheme", 0);
    s |= (theme & 0xFF) << 40;
    long spacing = lround(pref_double(@"buttonSpacing", 0));  // extra pt between traffic lights
    s |= (uint64_t)((spacing + 64) & 0xFF) << 48;
    return s;
}

// "#RRGGBB" or "#RRGGBBAA" -> RGBA packed as in shared.h (R in the low byte).
static uint64_t parse_color(NSString *hex) {
    unsigned int v = 0;
    NSString *h = [hex hasPrefix:@"#"] ? [hex substringFromIndex:1] : hex;
    if (![[NSScanner scannerWithString:h] scanHexInt:&v]) return 0xFF00A1E2;  // default amber
    if (h.length == 6) v = (v << 8) | 0xFF;
    uint64_t r = (v >> 24) & 0xFF, g = (v >> 16) & 0xFF, b = (v >> 8) & 0xFF, a = v & 0xFF;
    return r | (g << 8) | (b << 16) | (a << 24);
}

static uint64_t border_state(void) {
    uint64_t b = 0;
    id color = pref(@"borderColor");
    b |= parse_color([color isKindOfClass:NSString.class] ? color : @"#E2A100FF");
    double width = fmax(0, fmin(63, pref_double(@"borderWidth", 2)));
    b |= (uint64_t)lround(width * 4) << 32;
    if (pref_bool(@"borderEnabled", NO)) b |= MT_B_ENABLED;
    if (pref_bool(@"borderActiveOnly", YES)) b |= MT_B_ACTIVE_ONLY;
    if (!pref_bool(@"windowShadow", YES)) b |= MT_B_NO_SHADOW;
    long opacity = lround(fmax(0, fmin(100, pref_double(@"inactiveOpacity", 100))));
    b |= (uint64_t)opacity << 48;
    return b;
}

static uint64_t outline_state(void) {
    NSString *keys[] = {@"outlineOuter", @"outlineInner", @"shadowStrength", @"shadowSize"};
    const double max[] = {150, 150, 200, 200};
    uint64_t o = MT_OUTLINE_MAGIC << 56;
    for (int i = 0; i < 4; i++) o |= (uint64_t)lround(fmax(0, fmin(max[i], pref_double(keys[i], 100)))) << (8 * i);
    return o;
}

static NSDictionary<NSString *, NSNumber *> *app_states(void) {
    NSMutableDictionary *s = [NSMutableDictionary dictionary];
    id excluded = pref(@"excludedApps");
    if ([excluded isKindOfClass:NSArray.class])
        for (id k in excluded) if ([k isKindOfClass:NSString.class]) s[k] = @(MT_A_EXCLUDED);
    id automatic = pref(@"autoExcludedApps");
    if ([automatic isKindOfClass:NSDictionary.class])
        for (id k in automatic) if ([k isKindOfClass:NSString.class]) s[k] = @(MT_A_EXCLUDED);
    id custom = pref(@"customRadii");  // {bundleID: {top, bottom}}
    if ([custom isKindOfClass:NSDictionary.class])
        for (NSString *k in custom) {
            NSDictionary *v = custom[k];
            if (s[k] || ![v isKindOfClass:NSDictionary.class]) continue;
            s[k] = @(MT_A_CUSTOM_RADIUS | mt_encode_radius([v[@"top"] doubleValue], [v[@"bottom"] doubleValue]));
        }
    return s;
}

// --- notify states ---------------------------------------------------------

static void write_states(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
    if (g_settings_token < 0) notify_register_check(MT_N_SETTINGS, &g_settings_token);
    uint64_t global = global_state();
    notify_set_state(g_settings_token, global);
    if (g_border_token < 0) notify_register_check(MT_N_BORDER, &g_border_token);
    notify_set_state(g_border_token, border_state());
    if (g_outline_token < 0) notify_register_check(MT_N_OUTLINE, &g_outline_token);
    notify_set_state(g_outline_token, outline_state());

    NSDictionary *wanted = app_states();
    for (NSString *k in g_app_tokens.allKeys) {
        if (wanted[k]) continue;
        int t = g_app_tokens[k].intValue;
        notify_set_state(t, 0);
        notify_cancel(t);
        [g_app_tokens removeObjectForKey:k];
    }
    for (NSString *k in wanted) {
        int t;
        if (g_app_tokens[k]) {
            t = g_app_tokens[k].intValue;
        } else {
            NSString *name = [@MT_N_APP_PREFIX stringByAppendingString:k];
            if (notify_register_check(name.UTF8String, &t) != NOTIFY_STATUS_OK) continue;
            g_app_tokens[k] = @(t);
        }
        notify_set_state(t, [wanted[k] unsignedLongLongValue]);
    }
    notify_post(MT_N_SETTINGS);
    logf_(@"states written: global=0x%llx, %lu app rules", global, (unsigned long)wanted.count);
}

// --- install the core, set the environment --------------------------------

static NSString *run(NSString *path, NSArray *args) {
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:path];
    t.arguments = args;
    NSPipe *p = [NSPipe pipe];
    t.standardOutput = p;
    t.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![t launchAndReturnError:nil]) return @"";
    NSData *d = [p.fileHandleForReading readDataToEndOfFile];
    [t waitUntilExit];
    return [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @""
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static void install_core(void) {
    NSString *source = [[NSBundle.mainBundle.executablePath stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:[@"../Frameworks" stringByAppendingPathComponent:kCoreName]]
                           .stringByStandardizingPath;
    NSString *dir = getenv("MACTWEAK_DIR")
                        ? @(getenv("MACTWEAK_DIR"))
                        : [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/MacTweak"];
    g_core_path = [dir stringByAppendingPathComponent:kCoreName];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *fresh = [NSData dataWithContentsOfFile:source];
    if (!fresh) {
        logf_(@"core not found: %@", source);
        return;
    }
    if ([[NSData dataWithContentsOfFile:g_core_path] isEqual:fresh]) return;
    // Running apps may have the old file mapped: write a new file and rename it
    // over the old one instead of overwriting (the old inode stays valid).
    NSString *tmp = [dir stringByAppendingPathComponent:@".libmactweak.new"];
    [fresh writeToFile:tmp atomically:NO];
    chmod(tmp.fileSystemRepresentation, 0755);
    rename(tmp.fileSystemRepresentation, g_core_path.fileSystemRepresentation);
    logf_(@"core updated: %@", g_core_path);
}

// The core only loads when SIP is off and AMFI is told to step aside. On a Mac
// where either is still on, leave the environment alone instead of half-working.
static BOOL injection_possible(void) {
    NSString *sip = run(@"/usr/bin/csrutil", @[ @"status" ]);
    char args[1024] = {0};
    size_t len = sizeof args - 1;
    BOOL amfi_off = sysctlbyname("kern.bootargs", args, &len, NULL, 0) == 0 && strstr(args, "amfi_get_out_of_my_way=1");
    return [sip containsString:@"disabled"] && amfi_off;
}

static void set_environment(BOOL enabled) {
    static int possible = -1;
    if (possible < 0) {
        possible = injection_possible();
        if (!possible) logf_(@"SIP or AMFI is on: not loading the core into apps");
    }
    if (!possible) enabled = NO;
    NSString *current = run(@"/bin/launchctl", @[ @"getenv", @"DYLD_INSERT_LIBRARIES" ]);
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *p in [current componentsSeparatedByString:@":"])
        if (p.length && ![p isEqual:g_core_path]) [parts addObject:p];
    if (enabled) [parts addObject:g_core_path];
    NSString *value = [parts componentsJoinedByString:@":"];
    if ([value isEqual:current]) return;
    if (value.length)
        run(@"/bin/launchctl", @[ @"setenv", @"DYLD_INSERT_LIBRARIES", value ]);
    else
        run(@"/bin/launchctl", @[ @"unsetenv", @"DYLD_INSERT_LIBRARIES" ]);
    logf_(@"DYLD_INSERT_LIBRARIES = %@", value.length ? value : @"(unset)");
}

static void apply(void) {
    write_states();
    if (!test_mode()) set_environment(pref_bool(@"enabled", YES));
}

// --- notification -----------------------------------------------------------

static void notify_user(NSString *title, NSString *text) {
    NSString * (^esc)(NSString *) = ^(NSString *s) {
        return [[s stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"] stringByReplacingOccurrencesOfString:@"\""
                                                                                                         withString:@"\\\""];
    };
    NSString *script = [NSString
        stringWithFormat:@"display notification \"%@\" with title \"MacTweak\" subtitle \"%@\"", esc(text), esc(title)];
    run(@"/usr/bin/osascript", @[ @"-e", script ]);
}

// --- crash guard ------------------------------------------------------------

static NSMutableSet<NSString *> *g_seen_reports;
static NSMutableDictionary<NSString *, NSMutableArray<NSDate *> *> *g_crashes;

static void auto_exclude(NSString *bundle_id, NSString *name, NSString *reason) {
    NSMutableDictionary *automatic = [pref(@"autoExcludedApps") mutableCopy] ?: [NSMutableDictionary dictionary];
    if (![automatic isKindOfClass:NSMutableDictionary.class] || automatic[bundle_id]) return;
    NSString *date = [NSDateFormatter localizedStringFromDate:NSDate.date
                                                    dateStyle:NSDateFormatterShortStyle
                                                    timeStyle:NSDateFormatterShortStyle];
    automatic[bundle_id] = @{@"name" : name ?: bundle_id, @"reason" : reason, @"date" : date};
    pref_set(@"autoExcludedApps", automatic);
    write_states();
    notify_user([NSString stringWithFormat:@"%@ was excluded", name ?: bundle_id],
                [reason stringByAppendingString:@" You can undo this in MacTweak settings."]);
    logf_(@"auto-excluded %@ (%@)", bundle_id, reason);
}

static void inspect_report(NSString *path) {
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!text || [text rangeOfString:kCoreName].location == NSNotFound) return;
    NSRange nl = [text rangeOfString:@"\n"];
    if (nl.location == NSNotFound) return;
    NSData *headerData = [[text substringToIndex:nl.location] dataUsingEncoding:NSUTF8StringEncoding];
    NSData *bodyData = [[text substringFromIndex:nl.location + 1] dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *header = [NSJSONSerialization JSONObjectWithData:headerData options:0 error:nil];
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:nil];
    if (![body isKindOfClass:NSDictionary.class]) return;
    NSString *bundle_id = body[@"bundleInfo"][@"CFBundleIdentifier"] ?: header[@"bundleID"];
    NSString *name = header[@"app_name"] ?: bundle_id;
    if (![bundle_id isKindOfClass:NSString.class] || [bundle_id hasPrefix:@MT_DOMAIN]) return;

    // Is the core's code on the crashed thread?
    NSArray *images = body[@"usedImages"];
    NSInteger coreIndex = -1;
    for (NSUInteger i = 0; i < images.count; i++)
        if ([images[i][@"name"] isEqual:kCoreName]) coreIndex = (NSInteger)i;
    if (coreIndex < 0) return;
    BOOL guilty = NO;
    NSArray *threads = body[@"threads"];
    NSUInteger faulting = [body[@"faultingThread"] unsignedIntegerValue];
    if (faulting < threads.count)
        for (NSDictionary *frame in threads[faulting][@"frames"])
            if ([frame[@"imageIndex"] integerValue] == coreIndex) {
                guilty = YES;
                break;
            }

    if (guilty) {
        auto_exclude(bundle_id, name, @"MacTweak's library was in the crashing code.");
        return;
    }
    // The core was only loaded: still exclude after 3 crashes in 10 minutes.
    NSMutableArray *list = g_crashes[bundle_id] ?: [NSMutableArray array];
    g_crashes[bundle_id] = list;
    [list addObject:NSDate.date];
    [list filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDate *t, id _) {
              return -t.timeIntervalSinceNow < 600;
          }]];
    if (list.count >= 3) auto_exclude(bundle_id, name, @"Crashed 3 times in 10 minutes.");
}

static void scan_reports(NSString *dir) {
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil]) {
        if (![name hasSuffix:@".ips"] || [g_seen_reports containsObject:name]) continue;
        [g_seen_reports addObject:name];
        NSString *path = [dir stringByAppendingPathComponent:name];
        NSDate *mtime = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil].fileModificationDate;
        if (!mtime || [mtime compare:g_started] == NSOrderedAscending) continue;  // older than the agent
        inspect_report(path);
    }
}

static void watch_crashes(void) {
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/DiagnosticReports"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    g_seen_reports = [NSMutableSet set];
    g_crashes = [NSMutableDictionary dictionary];
    scan_reports(dir);
    int fd = open(dir.fileSystemRepresentation, O_EVTONLY);
    if (fd < 0) return;
    g_crash_watch =
        dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)fd, DISPATCH_VNODE_WRITE, dispatch_get_main_queue());
    __block BOOL pending = NO;
    dispatch_source_set_event_handler(g_crash_watch, ^{
        if (pending) return;
        pending = YES;
        // Reports are written in pieces; wait a little.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            pending = NO;
            scan_reports(dir);
        });
    });
    dispatch_resume(g_crash_watch);
}

// --- Finder -----------------------------------------------------------------

static BOOL process_start(pid_t pid, struct timeval *t) {
    struct kinfo_proc kp;
    size_t n = sizeof kp;
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    if (sysctl(mib, 4, &kp, &n, NULL, 0) != 0 || n == 0) return NO;
    *t = kp.kp_proc.p_starttime;
    return YES;
}

static void check_finder(void) {
    if (!pref_bool(@"enabled", YES) || !pref_bool(@"restartFinderAtLogin", YES)) return;
    pid_t pid = (pid_t)[run(@"/usr/bin/pgrep", @[ @"-x", @"Finder" ]) intValue];
    if (pid <= 0) return;
    struct timeval started;
    if (!process_start(pid, &started)) return;
    // Only at login: Finder started within the last 3 minutes.
    if (NSDate.date.timeIntervalSince1970 - started.tv_sec > 180) return;
    int t;
    uint64_t alive = 0;
    NSString *name = [NSString stringWithFormat:@"%s%d", MT_N_ALIVE_PREFIX, pid];
    notify_register_check(name.UTF8String, &t);
    notify_get_state(t, &alive);
    notify_cancel(t);
    if (alive) return;
    logf_(@"Finder started without the core; restarting it");
    run(@"/usr/bin/killall", @[ @"Finder" ]);
}

// ---------------------------------------------------------------------------

int main(void) {
    @autoreleasepool {
        setlinebuf(stderr);
        struct stat st;  // keep the log small
        if (fstat(STDERR_FILENO, &st) == 0 && S_ISREG(st.st_mode) && st.st_size > 512 * 1024) ftruncate(STDERR_FILENO, 0);

        g_started = NSDate.date;
        g_app_tokens = [NSMutableDictionary dictionary];
        install_core();
        apply();

        int t;
        notify_register_dispatch(MT_N_RELOAD, &t, dispatch_get_main_queue(), ^(int _) {
            (void)_;
            apply();
        });
        watch_crashes();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (!test_mode()) check_finder();
        });
        // When stopped, open windows return to the macOS default.
        signal(SIGTERM, SIG_IGN);
        g_sigterm = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(g_sigterm, ^{
            if (g_settings_token >= 0) notify_set_state(g_settings_token, 0);
            if (g_border_token >= 0) notify_set_state(g_border_token, 0);
            if (g_outline_token >= 0) notify_set_state(g_outline_token, 0);
            notify_post(MT_N_SETTINGS);
            exit(0);
        });
        dispatch_resume(g_sigterm);
        logf_(@"started (core: %@)", g_core_path);
        dispatch_main();
    }
}
