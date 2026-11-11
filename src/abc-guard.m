/* abc-guard: 按 App 粘滞的输入法守护进程。
 *
 * 规则：
 *   1. 切到一个 App 时，如果没记录过 → 切换为默认输入法（默认 ABC）。
 *   2. 你在某个 App 里手动换成中文输入法 → 记住这个选择，
 *      之后切走再切回来仍然是它，直到这个 App 被退出（进程结束）。
 *   3. App 退出后记录清除，下次启动回到默认输入法。
 *   4. 你在该 App 里手动切回默认输入法 → 清除记录。
 *
 * 用法：abc-guard [目标输入源ID]
 *   默认目标为 com.apple.keylayout.ABC
 */
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

static NSString *gTarget   = @"com.apple.keylayout.ABC";
static NSString *gLogPath;

/* pid -> 用户在该 App 里选的输入源（非默认） */
static NSMutableDictionary<NSNumber *, NSString *> *gSticky;

static pid_t          gFrontPid     = 0;
static NSString      *gLastSeen     = nil;
static BOOL           gGracePending = NO;
static NSTimeInterval gGraceUntil   = 0;

static NSTimeInterval now(void) { return [NSProcessInfo processInfo].systemUptime; }

static void logmsg(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"MM-dd HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"%@  %@\n", [f stringFromDate:[NSDate date]], s];
    FILE *fp = fopen(gLogPath.UTF8String, "a");
    if (fp) { fputs(line.UTF8String, fp); fclose(fp); }
}

static NSString *currentSourceID(void) {
    NSString *r = nil;
    TISInputSourceRef s = TISCopyCurrentKeyboardInputSource();
    if (s) {
        CFStringRef id = (CFStringRef)TISGetInputSourceProperty(s, kTISPropertyInputSourceID);
        if (id) r = [(__bridge NSString *)id copy];
        CFRelease(s);
    }
    return r;
}

static BOOL selectSource(NSString *want) {
    BOOL done = NO;
    CFArrayRef list = TISCreateInputSourceList(NULL, false);
    if (!list) return NO;
    for (CFIndex i = 0; i < CFArrayGetCount(list); i++) {
        TISInputSourceRef s = (TISInputSourceRef)CFArrayGetValueAtIndex(list, i);
        CFStringRef id = (CFStringRef)TISGetInputSourceProperty(s, kTISPropertyInputSourceID);
        if (id && CFStringCompare(id, (__bridge CFStringRef)want, 0) == kCFCompareEqualTo) {
            done = (TISSelectInputSource(s) == noErr);
            break;
        }
    }
    CFRelease(list);
    return done;
}

/* 该 App 该用什么输入法：有记录用记录的，没有就用默认 */
static void applyForApp(pid_t pid, NSString *name) {
    NSString *want = gSticky[@(pid)];
    BOOL isRecorded = (want != nil);
    if (!want) want = gTarget;

    if ([currentSourceID() isEqualToString:want]) return;

    if (selectSource(want)) {
        if (isRecorded) logmsg(@"%@ → 恢复你在这个 App 里选的 %@", name ?: @"?", want);
        else            logmsg(@"%@ → 默认 %@", name ?: @"?", gTarget);
    } else if (![want isEqualToString:gTarget] && selectSource(gTarget)) {
        logmsg(@"%@ → 记录的 %@ 已不可用，退回默认", name ?: @"?", want);
        [gSticky removeObjectForKey:@(pid)];
    }
}

static void tick(void) {
    NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
    if (!front) return;
    pid_t pid = front.processIdentifier;
    NSString *name = front.localizedName;

    /* —— 切换了 App —— */
    if (pid != gFrontPid) {
        gFrontPid = pid;
        gGraceUntil = now() + 0.45;   /* 系统可能在这之后恢复它自己记住的输入法 */
        gGracePending = YES;
        applyForApp(pid, name);
        gLastSeen = currentSourceID();
        return;
    }

    NSString *cur = currentSourceID();

    /* —— 宽限期：忽略期间的变化，结束时最后纠正一次 —— */
    if (gGracePending) {
        if (now() < gGraceUntil) { gLastSeen = cur; return; }
        gGracePending = NO;
        applyForApp(pid, name);
        gLastSeen = currentSourceID();
        return;
    }

    /* —— 用户手动换输入法 —— */
    if (cur && ![cur isEqualToString:gLastSeen ?: @""]) {
        if ([cur isEqualToString:gTarget]) {
            if (gSticky[@(pid)]) {
                [gSticky removeObjectForKey:@(pid)];
                logmsg(@"%@ 中手动切回默认 → 取消记忆", name ?: @"?");
            }
        } else {
            gSticky[@(pid)] = cur;
            logmsg(@"%@ 中手动切到 %@ → 记住，直到该 App 退出", name ?: @"?", cur);
        }
    }
    gLastSeen = cur;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc > 1 && argv[1][0] != '-')
            gTarget = [NSString stringWithUTF8String:argv[1]];

        gLogPath = [NSHomeDirectory() stringByAppendingPathComponent:
                    @"Library/Application Support/ABCInputSource/guard.log"];
        NSDictionary *attr = [NSFileManager.defaultManager attributesOfItemAtPath:gLogPath error:nil];
        if ([attr[NSFileSize] unsignedLongLongValue] > 512 * 1024)
            [NSFileManager.defaultManager createFileAtPath:gLogPath contents:nil attributes:nil];

        gSticky = [NSMutableDictionary dictionary];
        logmsg(@"启动（目标=%@；按 App 粘滞：默认它，手动换中文后该 App 保持，直到退出）", gTarget);

        [[[NSWorkspace sharedWorkspace] notificationCenter]
            addObserverForName:NSWorkspaceDidActivateApplicationNotification
                        object:nil queue:nil
                    usingBlock:^(NSNotification *note) { tick(); }];

        [[[NSWorkspace sharedWorkspace] notificationCenter]
            addObserverForName:NSWorkspaceDidTerminateApplicationNotification
                        object:nil queue:nil
                    usingBlock:^(NSNotification *note) {
                        NSRunningApplication *a = note.userInfo[NSWorkspaceApplicationKey];
                        if (!a) return;
                        if (gSticky[@(a.processIdentifier)]) {
                            [gSticky removeObjectForKey:@(a.processIdentifier)];
                            logmsg(@"%@ 已退出 → 清除记忆，下次启动回到默认", a.localizedName ?: @"?");
                        }
                    }];

        [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES
                                          block:^(NSTimer *t) { tick(); }];

        /* 启动时只记录现状、不做纠正：避免服务重启打断你正在用的输入法。
           （开机时的默认输入法由登录时运行的 abc-select 负责） */
        NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
        gFrontPid     = front ? front.processIdentifier : 0;
        gLastSeen     = currentSourceID();
        gGracePending = NO;
        tick();
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
