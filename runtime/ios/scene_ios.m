// UIScene sur iOS : voir scene_ios.h.
#include <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#include <SDL.h>
#include <SDL_syswm.h>
#include <stdio.h>
#include "scene_ios.h"

static UIWindowScene *connected;   // écrite et lue sur le thread principal

// Délégué nommé par UISceneDelegateClassName (ios/Info.plist.in).
@interface P2SceneDelegate : UIResponder <UIWindowSceneDelegate>
@end
@implementation P2SceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    connected = (UIWindowScene *)scene;
    CGRect bounds = connected.coordinateSpace.bounds;
    fprintf(stderr, "[ios] scène connectée : %.0fx%.0f points, échelle %.2f\n", bounds.size.width, bounds.size.height,
            connected.screen.scale);
}
- (void)sceneDidDisconnect:(UIScene *)scene {
    if (scene == connected) connected = nil;
}
@end

int rt_ios_scene_wait(double seconds) {
    if (![NSThread isMainThread]) return connected != nil;
    CFTimeInterval deadline = CACurrentMediaTime() + seconds;
    while (!connected && CACurrentMediaTime() < deadline)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
    if (!connected) fprintf(stderr, "[ios] aucune scène connectée après %.0f s\n", seconds);
    return connected != nil;
}

void rt_ios_scene_adopt(SDL_Window *sdl_window) {
    SDL_SysWMinfo info;
    SDL_VERSION(&info.version);
    if (!sdl_window || !SDL_GetWindowWMInfo(sdl_window, &info)) return;
    UIWindow *window = info.info.uikit.window;
    if (window && !window.windowScene && connected) window.windowScene = connected;
}
#endif
