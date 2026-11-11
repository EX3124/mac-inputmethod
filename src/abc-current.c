/* abc-current: 报告当前输入源 / 已启用的输入源（排查问题用）。
 *
 * 用法：abc-current          打印 "输入源ID (显示名)"
 *       abc-current --id     只打印输入源ID
 *       abc-current --list   列出当前已启用的输入源
 */
#include <Carbon/Carbon.h>
#include <stdio.h>
#include <string.h>

static void print_source(TISInputSourceRef s) {
    char id[256] = {0};
    CFStringRef a = (CFStringRef)TISGetInputSourceProperty(s, kTISPropertyInputSourceID);
    if (a) CFStringGetCString(a, id, sizeof id, kCFStringEncodingUTF8);
    printf("%s\n", id);
}

int main(int argc, char **argv) {
    const char *mode = (argc > 1) ? argv[1] : "";

    if (strcmp(mode, "--list") == 0) {
        CFArrayRef list = TISCreateInputSourceList(NULL, false);
        if (!list) { fprintf(stderr, "读取失败\n"); return 1; }
        for (CFIndex i = 0; i < CFArrayGetCount(list); i++)
            print_source((TISInputSourceRef)CFArrayGetValueAtIndex(list, i));
        CFRelease(list);
        return 0;
    }

    TISInputSourceRef s = TISCopyCurrentKeyboardInputSource();
    if (!s) { fprintf(stderr, "读取失败：拿不到当前输入源\n"); return 1; }

    if (strcmp(mode, "--id") == 0) {
        print_source(s);
    } else {
        char id[256] = {0}, name[256] = {0};
        CFStringRef a = (CFStringRef)TISGetInputSourceProperty(s, kTISPropertyInputSourceID);
        CFStringRef b = (CFStringRef)TISGetInputSourceProperty(s, kTISPropertyLocalizedName);
        if (a) CFStringGetCString(a, id, sizeof id, kCFStringEncodingUTF8);
        if (b) CFStringGetCString(b, name, sizeof name, kCFStringEncodingUTF8);
        printf("%s (%s)\n", id, name);
    }
    CFRelease(s);
    return 0;
}
