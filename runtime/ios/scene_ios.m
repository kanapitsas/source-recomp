// UIScene sur iOS : voir scene_ios.h.
#include <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <SDL.h>
#include <SDL_syswm.h>
#include <math.h>
#include <stdatomic.h>
#include <stdio.h>
#include "scene_ios.h"

// La scène elle-même n'est touchée que par le thread principal ; ce que les autres
// threads lisent (SDL, le jeu) est copié dans des atomiques.
static UIWindowScene *connected;
static _Atomic int scene_w, scene_h;   // taille de l'écran de la scène (paysage), 0 sans scène
static _Atomic int scene_orientation;  // UIInterfaceOrientation de la scène
static _Atomic int waited;             // l'attente de la scène n'a lieu qu'une fois

static void record_scene(UIWindowScene *scene) {
    // App en paysage seulement : largeur = le plus grand côté.
    CGSize size = scene.coordinateSpace.bounds.size;
    atomic_store(&scene_w, (int)lround(fmax(size.width, size.height)));
    atomic_store(&scene_h, (int)lround(fmin(size.width, size.height)));
    atomic_store(&scene_orientation, (int)scene.interfaceOrientation);
}

// Délégué nommé par UISceneDelegateClassName (ios/Info.plist.in).
@interface P2SceneDelegate : UIResponder <UIWindowSceneDelegate>
@end
@implementation P2SceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    connected = (UIWindowScene *)scene;
    record_scene(connected);
    CGRect bounds = connected.coordinateSpace.bounds;
    fprintf(stderr, "[ios] scène connectée : %.0fx%.0f points, échelle %.2f\n", bounds.size.width, bounds.size.height,
            connected.screen.scale);
}
// Dépliage ou pliage de l'appareil, rotation : la scène change de taille.
- (void)windowScene:(UIWindowScene *)windowScene didUpdateCoordinateSpace:(id<UICoordinateSpace>)previousCoordinateSpace
    interfaceOrientation:(UIInterfaceOrientation)previousInterfaceOrientation traitCollection:(UITraitCollection *)previousTraitCollection {
    (void)previousCoordinateSpace; (void)previousInterfaceOrientation; (void)previousTraitCollection;
    if (windowScene == connected) record_scene(connected);
}
- (void)sceneDidDisconnect:(UIScene *)scene {
    if (scene != connected) return;
    connected = nil;
    atomic_store(&scene_w, 0); atomic_store(&scene_h, 0); atomic_store(&scene_orientation, 0);
}
@end

// SDL 2.30.9 tire l'orientation de l'écran (modes d'affichage, bornes, taille des
// fenêtres plein écran) de -[UIApplication statusBarOrientation], que le cycle de vie
// par scènes ne tient plus à jour : l'écran de l'iPhone Duo (466×678) était alors
// annoncé en portrait au jeu, alors que l'app est paysage seulement. On répond avec
// l'orientation de la scène, ou paysage tant qu'aucune scène n'est connectée (SDL
// calcule ses modes dès SDL_Init, avant la connexion).
//
// Sur le grand écran du Duo, UIScreen.mainScreen reste le petit (678×466) alors que la
// fenêtre fait 951×669 points. SDL en tire son mode d'affichage de bureau, et à chaque
// retour au premier plan il y ramène la fenêtre plein écran : le jeu se retrouvait dans
// un coin de la surface. Une fois la scène connectée, mainScreen.bounds est donc celle
// de la scène (même taille sur les autres appareils) ; ios/main_ios.c attend la scène
// avant que SDL ne lise l'écran.
static CGRect (*original_screen_bounds)(id, SEL);

__attribute__((constructor)) static void install_screen_overrides(void) {
    Method orientation = class_getInstanceMethod(UIApplication.class, @selector(statusBarOrientation));
    if (orientation)
        method_setImplementation(orientation, imp_implementationWithBlock(^UIInterfaceOrientation(UIApplication *application) {
            (void)application;
            UIInterfaceOrientation value = (UIInterfaceOrientation)atomic_load(&scene_orientation);
            return UIInterfaceOrientationIsLandscape(value) ? value : UIInterfaceOrientationLandscapeRight;
        }));
    Method bounds = class_getInstanceMethod(UIScreen.class, @selector(bounds));
    if (!bounds) return;
    original_screen_bounds = (CGRect (*)(id, SEL))method_getImplementation(bounds);
    method_setImplementation(bounds, imp_implementationWithBlock(^CGRect(UIScreen *screen) {
        int w = atomic_load(&scene_w), h = atomic_load(&scene_h);
        if (w && h && screen == UIScreen.mainScreen) return CGRectMake(0, 0, w, h);
        return original_screen_bounds(screen, @selector(bounds));
    }));
}

int rt_ios_scene_wait(double seconds) {
    if (!atomic_load(&scene_w) && [NSThread isMainThread] && !atomic_exchange(&waited, 1)) {
        CFTimeInterval deadline = CACurrentMediaTime() + seconds;
        while (!connected && CACurrentMediaTime() < deadline)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
        if (!connected) fprintf(stderr, "[ios] aucune scène connectée après %.0f s\n", seconds);
    }
    return atomic_load(&scene_w) != 0;
}

void rt_ios_scene_adopt(SDL_Window *sdl_window) {
    SDL_SysWMinfo info;
    SDL_VERSION(&info.version);
    if (!sdl_window || !SDL_GetWindowWMInfo(sdl_window, &info)) return;
    UIWindow *window = info.info.uikit.window;
    if (window && !window.windowScene && connected) window.windowScene = connected;
}
#endif
