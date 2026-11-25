// UIScene sur iOS (runtime/ios/scene_ios.m). Une app liée au SDK 27 doit
// déclarer son cycle de vie par scènes (UIApplicationSceneManifest de
// ios/Info.plist.in) : sans cela, iOS la lance en mode de compatibilité,
// écran de 1334×750 points avec des bandes noires sur l'iPhone Duo.
// SDL2 2.30.9 ignore les scènes ; ce fichier fournit le délégué de scène et
// rattache les fenêtres SDL à la scène connectée.
#pragma once

// Thread principal : au premier appel, sert la boucle d'UIKit jusqu'à ce que la scène
// soit connectée (au plus `seconds`) ; ensuite, ou depuis un autre thread, ne fait
// qu'indiquer si elle l'est. Retourne 1 si une scène est connectée.
int rt_ios_scene_wait(double seconds);
// Rattache la fenêtre UIKit d'une fenêtre SDL à la scène connectée si elle n'en
// a pas encore (UIKit la redimensionne alors à la scène). Sans effet sans scène.
typedef struct SDL_Window SDL_Window;
void rt_ios_scene_adopt(SDL_Window *sdl_window);
