// UIScene sur iOS (runtime/ios/scene_ios.m). Une app liée au SDK 27 doit
// déclarer son cycle de vie par scènes (UIApplicationSceneManifest de
// ios/Info.plist.in) : sans cela, iOS la lance en mode de compatibilité,
// écran de 1334×750 points avec des bandes noires sur l'iPhone Duo.
// SDL2 2.30.9 ignore les scènes ; ce fichier fournit le délégué de scène et
// rattache les fenêtres SDL à la scène connectée.
#pragma once

// 1 sur un iPhone Duo (identifiant de modèle iPhone19,4 ; SIMULATOR_MODEL_IDENTIFIER au
// simulateur), 0 ailleurs. Utilisable depuis n'importe quel thread.
int rt_ios_is_iphone_duo(void);

// Thread principal : au premier appel, sert la boucle d'UIKit jusqu'à ce que la scène
// soit connectée (au plus `seconds`) ; ensuite, ou depuis un autre thread, ne fait
// qu'indiquer si elle l'est. Retourne 1 si une scène est connectée.
int rt_ios_scene_wait(double seconds);
// Rattache la fenêtre UIKit d'une fenêtre SDL à la scène connectée si elle n'en
// a pas encore (UIKit la redimensionne alors à la scène). Sans effet sans scène.
typedef struct SDL_Window SDL_Window;
void rt_ios_scene_adopt(SDL_Window *sdl_window);
// Retire les observateurs de branchement d'écran de SDL (SDL_DisplayWatch). L'app n'utilise
// qu'un écran ; sur l'iPhone Duo, plier ou déplier l'appareil débranche un UIScreen et
// SDL_DisplayWatch plantait dans UIKit_DelDisplay. À appeler après SDL_Init.
void rt_ios_scene_ignore_screen_changes(void);
// Thread principal, une fois par SDL_PollEvent : si la taille de la fenêtre SDL n'est plus
// celle de sa vue (SDL ramène la fenêtre plein écran à son mode d'affichage de bureau, figé
// au lancement, quand l'app revient au premier plan : sur le Duo plié ou déplié entre-temps,
// le jeu se retrouvait rogné ou dans un coin), force une mise en page : SDL renvoie alors
// l'événement de redimensionnement avec la vraie taille. Peu coûteux si rien ne change.
void rt_ios_scene_resync(SDL_Window *sdl_window);
// Thread principal. En portrait sur le grand écran de l'iPhone Duo, le jeu occupe la moitié
// haute de l'écran et une seconde fenêtre la moitié basse, pour les commandes tactiles :
// rt_ios_scene_split() dit si c'est le cas, rt_ios_scene_controls_view() rend alors la vue
// (UIView *) de cette seconde fenêtre, sinon NULL.
int rt_ios_scene_split(void);
void *rt_ios_scene_controls_view(void);
