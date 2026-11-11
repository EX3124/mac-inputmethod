/* abc-select: 切换当前输入源，并回读校验是否真的切过去了。
 *
 * 用法：abc-select [输入源ID] [--wait 毫秒]
 *   默认输入源ID为 com.apple.keylayout.ABC
 *   退出码 0 表示成功（或本来就已经是它），1 表示失败。
 */
#include <Carbon/Carbon.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void get_id(char *buf, size_t n) {
    buf[0] = 0;
    TISInputSourceRef s = TISCopyCurrentKeyboardInputSource();
    if (!s) return;
    CFStringRef id = (CFStringRef)TISGetInputSourceProperty(s, kTISPropertyInputSourceID);
    if (id) CFStringGetCString(id, buf, (CFIndex)n, kCFStringEncodingUTF8);
    CFRelease(s);
}

static int set_source(const char *want) {
    CFStringRef w = CFStringCreateWithCString(NULL, want, kCFStringEncodingUTF8);
    CFArrayRef list = TISCreateInputSourceList(NULL, false);
    int found = 0;
    if (list) {
        for (CFIndex i = 0; i < CFArrayGetCount(list); i++) {
            TISInputSourceRef s = (TISInputSourceRef)CFArrayGetValueAtIndex(list, i);
            CFStringRef id = (CFStringRef)TISGetInputSourceProperty(s, kTISPropertyInputSourceID);
            if (id && CFStringCompare(id, w, 0) == kCFCompareEqualTo) {
                if (TISSelectInputSource(s) == noErr) found = 1;
            }
        }
        CFRelease(list);
    }
    CFRelease(w);
    return found;
}

int main(int argc, char **argv) {
    const char *want = "com.apple.keylayout.ABC";
    int wait_ms = 400;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--wait") == 0 && i + 1 < argc) {
            wait_ms = atoi(argv[++i]);
        } else if (strncmp(argv[i], "-h", 2) == 0) {
            printf("用法: abc-select [输入源ID] [--wait 毫秒]\n");
            printf("例如: abc-select com.apple.keylayout.ABC\n");
            return 0;
        } else {
            want = argv[i];
        }
    }

    char cur[256];
    get_id(cur, sizeof cur);
    if (strcmp(cur, want) == 0) { printf("already %s\n", want); return 0; }

    if (!set_source(want)) {
        printf("FAILED: 未找到可用的输入源 %s（是否未在系统中启用？）\n", want);
        printf("当前可用输入源请在 系统设置 → 键盘 → 输入法 中查看。\n");
        return 1;
    }
    usleep((useconds_t)wait_ms * 1000);

    get_id(cur, sizeof cur);
    if (strcmp(cur, want) == 0) { printf("switched to %s\n", want); return 0; }
    printf("FAILED to switch to %s (现在是 %s)\n", want, cur);
    return 1;
}
