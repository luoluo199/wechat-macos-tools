// wrapper.m — WeChat 入口包装器
// 先加载 unsharingtype.dylib，然后 exec 真正的 WeChat_orig
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <unistd.h>
#import <string.h>
#import <libgen.h>

int main(int argc, char *argv[]) {
    // 获取自身路径
    char selfPath[4096];
    uint32_t size = sizeof(selfPath);
    _NSGetExecutablePath(selfPath, &size);

    char *dir = dirname(selfPath);

    // 加载 dylib
    char dylibPath[4096];
    snprintf(dylibPath, sizeof(dylibPath), "%s/unsharingtype.dylib", dir);
    void *handle = dlopen(dylibPath, RTLD_NOW);
    if (handle) {
        NSLog(@"[Wrapper] ✅ dylib 已加载");
    } else {
        NSLog(@"[Wrapper] ⚠️ dylib 加载失败: %s", dlerror());
    }

    // exec 真正的 WeChat
    char origPath[4096];
    snprintf(origPath, sizeof(origPath), "%s/WeChat_orig", dir);

    argv[0] = origPath;
    execv(origPath, argv);

    // exec 失败
    perror("execv");
    return 1;
}
