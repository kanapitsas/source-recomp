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
#include <string.h>
#include "env_ios.h"
#include "scene_ios.h"

// La scène elle-même n'est touchée que par le thread principal ; ce que les autres
// threads lisent (SDL, le jeu) est copié dans des atomiques.
static UIWindowScene *connected;
static _Atomic int scene_w, scene_h;   // taille de l'écran de la scène (paysage), 0 sans scène
static _Atomic int scene_orientation;  // UIInterfaceOrientation de la scène
static UIWindow *tracked_window;       // fenêtre du jeu (thread principal)
static void apply_layout(void);
static _Atomic int waited;             // l'attente de la scène n'a lieu qu'une fois

// Grand écran d'un téléphone (inférieur de l'iPhone Duo : 669 pt de côté court, contre 440 au
// plus pour les autres iPhone) : le jeu y tient en portrait dans la moitié haute, les
// commandes dans la moitié basse, comme une console à deux écrans. P2_PORTRAIT_SPLIT=0 : jamais.
static BOOL wide_phone_display(UIWindowScene *scene) {
    CGSize size = scene.coordinateSpace.bounds.size;
    return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone && fmin(size.width, size.height) >= 500
        && rt_ios_env_flag("P2_PORTRAIT_SPLIT", 1);
}
// Zone du jeu dans la scène : toute la scène, ou la moitié haute en portrait sur ce grand écran.
static CGRect game_rect(UIWindowScene *scene) {
    CGRect bounds = scene.coordinateSpace.bounds;
    if (bounds.size.height > bounds.size.width && wide_phone_display(scene)) bounds.size.height = floor(bounds.size.height / 2);
    return bounds;
}

static void record_scene(UIWindowScene *scene) {
    // La fenêtre du jeu est toujours plus large que haute : largeur = le plus grand côté.
    CGSize size = game_rect(scene).size;
    atomic_store(&scene_w, (int)lround(fmax(size.width, size.height)));
    atomic_store(&scene_h, (int)lround(fmin(size.width, size.height)));
    atomic_store(&scene_orientation, (int)scene.interfaceOrientation);
    // SDL tire les orientations permises de ce réglage chaque fois qu'UIKit les demande
    // (Info.plist y ajoute le portrait pour le Duo seulement).
    const char *wanted = wide_phone_display(scene) ? "LandscapeLeft LandscapeRight Portrait" : "LandscapeLeft LandscapeRight";
    const char *current = SDL_GetHint(SDL_HINT_ORIENTATIONS);
    if (!current || strcmp(current, wanted)) {
        SDL_SetHint(SDL_HINT_ORIENTATIONS, wanted);
        [tracked_window.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
    }
}

// Info.plist autorise le portrait : iOS lance l'app dans l'orientation où il voit le téléphone
// (la scène connectée avant main() en porte déjà le résultat). Sur les écrans ordinaires, l'app
// est en paysage seulement : le moteur choisit sa résolution au démarrage, et une surface de
// portrait laissait le jeu dans un coin ; on y demande le paysage dès la connexion. Sur le grand
// écran du Duo, on garde le choix d'iOS (paysage, ou portrait coupé en deux) : la fenêtre du jeu
// est mise à sa taille avant que le moteur ne crée sa surface (rt_ios_scene_adopt). On ne lit pas
// UIDevice.orientation : c'est l'orientation du corps du téléphone, pas de l'écran intérieur, qui
// annonce « portrait » dans la position large.
// UIKit ne tourne une scène que si une fenêtre y porte un contrôleur qui le permet : tant que SDL
// n'a pas créé la sienne, une fenêtre noire tient la place (paysage seulement sauf grand écran).
static BOOL bootstrap_allows_portrait;
@interface P2LandscapeController : UIViewController
@end
@implementation P2LandscapeController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return bootstrap_allows_portrait ? UIInterfaceOrientationMaskLandscape | UIInterfaceOrientationMaskPortrait
                                     : UIInterfaceOrientationMaskLandscape;
}
- (BOOL)prefersStatusBarHidden { return YES; }
@end
static UIWindow *bootstrap_window;
static void request_orientations(UIWindowScene *scene, UIInterfaceOrientationMask mask) {
    UIWindowSceneGeometryPreferencesIOS *preferences = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:mask];
    [scene requestGeometryUpdateWithPreferences:preferences errorHandler:^(NSError *error) {
        fprintf(stderr, "[ios] rotation refusée : %s\n", error.localizedDescription.UTF8String);
    }];
}
void rt_ios_touch_controls_rehost(void);       // touch_controls.m

// Délégué nommé par UISceneDelegateClassName (ios/Info.plist.in).
@interface P2SceneDelegate : UIResponder <UIWindowSceneDelegate>
@end
@implementation P2SceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    connected = (UIWindowScene *)scene;
    record_scene(connected);
    [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
    bootstrap_allows_portrait = wide_phone_display(connected);
    bootstrap_window = [[UIWindow alloc] initWithWindowScene:connected];
    bootstrap_window.rootViewController = [P2LandscapeController new];
    bootstrap_window.backgroundColor = UIColor.blackColor;
    [bootstrap_window makeKeyAndVisible];
    if (!bootstrap_allows_portrait) request_orientations(connected, UIInterfaceOrientationMaskLandscape);
    CGRect bounds = connected.coordinateSpace.bounds;
    fprintf(stderr, "[ios] scène connectée : %.0fx%.0f points, échelle %.2f\n", bounds.size.width, bounds.size.height,
            connected.screen.scale);
}
// Dépliage ou pliage de l'appareil, rotation : la scène change de taille.
- (void)windowScene:(UIWindowScene *)windowScene didUpdateCoordinateSpace:(id<UICoordinateSpace>)previousCoordinateSpace
    interfaceOrientation:(UIInterfaceOrientation)previousInterfaceOrientation traitCollection:(UITraitCollection *)previousTraitCollection {
    (void)previousCoordinateSpace; (void)previousInterfaceOrientation; (void)previousTraitCollection;
    if (windowScene != connected) return;
    record_scene(connected);
    apply_layout();
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
    // Le moteur demande la saisie de texte (SDL_StartTextInput) : SDL ouvre alors le clavier à
    // l'écran, que rien dans les commandes tactiles ne permet de refermer (sur le Duo, plié puis
    // déplié, il recouvrait la moitié du jeu). Les touches d'un clavier matériel passent toujours ;
    // P2_SCREEN_KEYBOARD=1 rend le clavier à l'écran.
    if (!rt_ios_env_flag("P2_SCREEN_KEYBOARD", 0)) SDL_SetHint(SDL_HINT_ENABLE_SCREEN_KEYBOARD, "0");
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
    if (![NSThread isMainThread]) return atomic_load(&scene_w) != 0;
    if (!connected && !atomic_exchange(&waited, 1)) {
        CFTimeInterval deadline = CACurrentMediaTime() + seconds;
        while (!connected && CACurrentMediaTime() < deadline)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
        if (!connected) fprintf(stderr, "[ios] aucune scène connectée après %.0f s\n", seconds);
    }
    // Hors grand écran, le jeu ne naît qu'en paysage (voir request_orientations) : la scène,
    // connectée avant même main(), peut encore être en portrait.
    static BOOL landscape_waited;
    if (connected && !landscape_waited && !wide_phone_display(connected)) {
        landscape_waited = YES;
        CFTimeInterval start = CACurrentMediaTime();
        while (connected.coordinateSpace.bounds.size.height > connected.coordinateSpace.bounds.size.width && CACurrentMediaTime() < start + 3)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
        CGSize size = connected.coordinateSpace.bounds.size;
        fprintf(stderr, "[ios] scène en paysage : %.0fx%.0f après %.2f s\n", size.width, size.height, CACurrentMediaTime() - start);
        record_scene(connected);   // le délégué n'a peut-être pas encore vu la rotation
    }
    return atomic_load(&scene_w) != 0;
}

void rt_ios_scene_ignore_screen_changes(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class watch = NSClassFromString(@"SDL_DisplayWatch");   // SDL_uikitmodes.m, observateur de classe
        if (!watch) return;
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center removeObserver:watch name:@"UIScreenDidConnectNotification" object:nil];
        [center removeObserver:watch name:@"UIScreenDidDisconnectNotification" object:nil];
    });
}

void rt_ios_scene_adopt(SDL_Window *sdl_window) {
    SDL_SysWMinfo info;
    SDL_VERSION(&info.version);
    if (!sdl_window || !SDL_GetWindowWMInfo(sdl_window, &info)) return;
    UIWindow *window = info.info.uikit.window;
    if (window && !window.windowScene && connected) window.windowScene = connected;
    tracked_window = window;
    bootstrap_window.hidden = YES;   // la fenêtre de SDL prend la place
    bootstrap_window = nil;
    // Avant que le moteur ne crée sa surface : la fenêtre a déjà la taille de la zone du jeu (moitié
    // haute en portrait coupé en deux) et la moitié basse porte déjà les commandes.
    apply_layout();
}

// Moitié basse de l'écran en portrait : sa propre fenêtre, qui porte les commandes tactiles
// (celle de SDL ne couvre que la moitié haute). Elle suit les orientations de celle du jeu.
@interface P2ControlsController : UIViewController
@end
@implementation P2ControlsController
- (UIViewController *)game { return tracked_window.rootViewController; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return self.game.supportedInterfaceOrientations; }
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return self.game.prefersHomeIndicatorAutoHidden; }
@end
static UIWindow *controls_window;

// Thread principal : fenêtre du jeu en haut et fenêtre des commandes en bas en portrait sur
// le grand écran ; ailleurs, fenêtre du jeu seule, à la taille de la scène.
static void apply_layout(void) {
    if (!connected || !tracked_window) return;
    CGRect bounds = connected.coordinateSpace.bounds, game = game_rect(connected);
    BOOL split = !CGRectEqualToRect(game, bounds);
    static CGRect last_bounds; static NSInteger last_orientation;
    if (!CGRectEqualToRect(last_bounds, bounds) || last_orientation != connected.interfaceOrientation) {
        last_bounds = bounds; last_orientation = connected.interfaceOrientation;
        fprintf(stderr, "[ios] scène %.0fx%.0f orientation %ld, jeu %.0fx%.0f, coupé %d, fenêtre %.0fx%.0f\n", bounds.size.width, bounds.size.height,
                (long)last_orientation, game.size.width, game.size.height, split, tracked_window.frame.size.width, tracked_window.frame.size.height);
    }
    // La fenêtre suit toujours la zone du jeu : UIKit ne la redimensionne pas toujours lui-même
    // (lancé replié sur le Duo, puis déplié, le jeu restait dans le coin à la taille de l'écran
    // extérieur).
    CGRect wanted = split ? game : bounds;
    if (!CGRectEqualToRect(tracked_window.frame, wanted)) {
        tracked_window.frame = wanted;
        [tracked_window layoutIfNeeded];   // SDL envoie alors la taille de la vue (viewDidLayoutSubviews)
    }
    if (!split) { controls_window.hidden = YES; rt_ios_touch_controls_rehost(); return; }
    CGRect below = CGRectMake(0, CGRectGetMaxY(game), bounds.size.width, bounds.size.height - CGRectGetMaxY(game));
    if (!controls_window) {
        controls_window = [[UIWindow alloc] initWithWindowScene:connected];
        controls_window.rootViewController = [P2ControlsController new];
        controls_window.rootViewController.view.backgroundColor = UIColor.blackColor;
        controls_window.backgroundColor = UIColor.blackColor;
    }
    if (controls_window.windowScene != connected) controls_window.windowScene = connected;
    if (!CGRectEqualToRect(controls_window.frame, below)) controls_window.frame = below;
    if (controls_window.hidden) controls_window.hidden = NO;   // sans devenir la fenêtre clé : les événements restent à SDL
    [controls_window layoutIfNeeded];
    rt_ios_touch_controls_rehost();
}

int rt_ios_scene_split(void) { return controls_window && !controls_window.hidden; }
void *rt_ios_scene_controls_view(void) { return rt_ios_scene_split() ? (__bridge void *)controls_window.rootViewController.view : NULL; }

void rt_ios_scene_resync(SDL_Window *sdl_window) {
    UIView *view = tracked_window.rootViewController.view;
    if (!sdl_window || !view || ![NSThread isMainThread]) return;
    apply_layout();
    int w = 0, h = 0;
    SDL_GetWindowSize(sdl_window, &w, &h);
    CGSize size = view.bounds.size;   // mêmes troncatures que viewDidLayoutSubviews de SDL
    if ((int)size.width == w && (int)size.height == h) return;
    [view setNeedsLayout];
    [view layoutIfNeeded];
}
#endif
