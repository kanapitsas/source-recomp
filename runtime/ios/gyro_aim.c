// Visée au gyroscope : calcul pur, testé sur le Mac (tests/checks_gyro_aim.c) ;
// les capteurs sont lus par touch_controls.m.
#include "gyro_aim.h"
#include "env_ios.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

void rt_gyro_params_from_env(rt_gyro_params *p) {
    p->counts_per_rad = RT_GYRO_COUNTS_PER_RAD * rt_ios_env_double("P2_GYRO_SPEED", 1, 1e-9);   // > 0
    p->tighten = rt_ios_env_double("P2_GYRO_TIGHTEN", 0.05, 0);
    p->screen_by_gravity = 0;   // posé par l'app sur l'iPhone Duo (gyro_ios.m)
}

// P2_GYRO=1 ou 0 ; sinon le défaut du jeu.
int rt_gyro_enabled(int on_by_default) { return rt_ios_env_flag("P2_GYRO", on_by_default); }

// Petite rotation : atténuée en proportion (0 à l'arrêt, inchangée au seuil),
// sans saut à la limite ; ce qu'on perd en visée très lente, on le gagne en
// stabilité quand on tient le téléphone sans bouger.
static double tightened(double rate, double threshold) {
    double a = fabs(rate);
    return a < threshold ? rate * (a / threshold) : rate;
}

int rt_gyro_delta(const rt_gyro_params *p, const double w[3], const double g[3], int orient, double dt,
                  double out[2]) {
    out[0] = out[1] = 0;
    if (!orient || !(dt > 0) || dt > 0.1) return 0;   // trou dans les échantillons : rien plutôt qu'un saut
    double norm = sqrt(g[0] * g[0] + g[1] * g[1] + g[2] * g[2]);
    if (!(norm > 0.3)) return 0;                       // gravité pas encore estimée
    // Verticale réelle vers le haut, et axe horizontal de l'écran vers la droite.
    double up[3] = {-g[0] / norm, -g[1] / norm, -g[2] / norm};
    // Axe horizontal de l'écran vers la droite, dans le repère de l'appareil. La gravité projetée dans
    // le plan de l'écran (xy) pointe vers son bord du bas ; la droite est ce bord du bas, vers le haut,
    // tourné d'un quart de tour autour de z (qui sort de l'écran) : (-gy, gx, 0). Cela ne suppose rien
    // sur l'orientation des axes de l'appareil par rapport à l'écran (celle de l'iPhone Duo, plié
    // ou non, n'est pas celle d'un iPhone) et suit un téléphone tenu un peu de travers. Quasi à plat,
    // ce bord n'est plus défini : on retombe sur l'orientation de l'interface (y en paysage, x en
    // portrait droit). Seulement sur l'iPhone Duo (screen_by_gravity) : couché sur le côté, la gravité
    // d'un autre iPhone tire vers le côté de l'écran alors que le jeu reste en paysage, et prendre ce
    // côté pour le bas de l'écran ferait tourner le tangage autour du mauvais axe.
    double right[3], plane = sqrt(g[0] * g[0] + g[1] * g[1]);
    if (p->screen_by_gravity && plane >= 0.35 * norm) {
        right[0] = -g[1] / plane; right[1] = g[0] / plane; right[2] = 0;
    } else {
        right[0] = orient == RT_BACKTAP_PORTRAIT ? 1 : 0;
        right[1] = orient == RT_BACKTAP_PORTRAIT ? 0 : orient;
        right[2] = 0;
    }
    double yaw = w[0] * up[0] + w[1] * up[1] + w[2] * up[2];   // > 0 : on tourne vers la gauche
    double pitch = w[0] * right[0] + w[1] * right[1] + w[2] * right[2];   // > 0 : haut de l'écran vers soi
    yaw = tightened(yaw, p->tighten);
    pitch = tightened(pitch, p->tighten);
    out[0] = -yaw * dt * p->counts_per_rad;
    out[1] = -pitch * dt * p->counts_per_rad;
    return out[0] != 0 || out[1] != 0;
}
