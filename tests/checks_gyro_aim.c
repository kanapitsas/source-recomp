// Visée au gyroscope (runtime/ios/gyro_aim.c) : sens du lacet et du tangage
// dans les deux paysages et à plat, atténuation, trous, variables.
#include "checks.h"
#include <math.h>
#include <stdlib.h>
#include "../runtime/ios/gyro_aim.c"

static rt_gyro_params gyro_test_params(void) {
    rt_gyro_params p = {1000, 0.05, 0};
    return p;
}
static void gyro_turn(int orient, const double g[3], const double w[3], double out[2]) {
    rt_gyro_params p = gyro_test_params();
    assert(rt_gyro_delta(&p, w, g, orient, 0.01, out));
}

RT_CHECK(gyro_yaw_and_pitch_follow_the_phone_in_both_landscapes) {
    double out[2];
    // Paysage gauche, téléphone debout : y de l'appareil vers la droite de
    // l'écran, haut de l'écran = -x, gravité vers +x.
    const double left_g[3] = {1, 0, 0};
    gyro_turn(1, left_g, (double[3]){-1, 0, 0}, out);   // on tourne sur soi vers la gauche
    assert(out[0] < 0 && fabs(out[1]) < 1e-9);
    assert(fabs(out[0] + 10) < 1e-9);                  // 1 rad/s pendant 10 ms à 1000 comptes/rad
    gyro_turn(1, left_g, (double[3]){0, 1, 0}, out);    // haut de l'écran vers soi : regarder en haut
    assert(out[1] < 0 && fabs(out[0]) < 1e-9);
    // Paysage droit : tout est retourné dans le repère de l'appareil.
    const double right_g[3] = {-1, 0, 0};
    gyro_turn(-1, right_g, (double[3]){1, 0, 0}, out);  // vers la gauche
    assert(out[0] < 0);
    gyro_turn(-1, right_g, (double[3]){0, -1, 0}, out); // haut de l'écran vers soi
    assert(out[1] < 0);
    gyro_turn(-1, right_g, (double[3]){0, 1, 0}, out);  // haut de l'écran vers l'avant : regarder en bas
    assert(out[1] > 0);
}

// Portrait, téléphone droit : gravité selon -y, haut de l'écran = +y, droite de l'écran = +x.
RT_CHECK(gyro_yaw_and_pitch_follow_the_phone_in_portrait) {
    double out[2];
    const double up_g[3] = {0, -1, 0};
    gyro_turn(RT_BACKTAP_PORTRAIT, up_g, (double[3]){0, 1, 0}, out);    // on tourne sur soi vers la gauche
    assert(out[0] < 0 && fabs(out[1]) < 1e-9 && fabs(out[0] + 10) < 1e-9);
    gyro_turn(RT_BACKTAP_PORTRAIT, up_g, (double[3]){1, 0, 0}, out);    // haut de l'écran vers soi : regarder en haut
    assert(out[1] < 0 && fabs(out[0]) < 1e-9 && fabs(out[1] + 10) < 1e-9);
    gyro_turn(RT_BACKTAP_PORTRAIT, up_g, (double[3]){-1, 0, 0}, out);   // haut vers l'avant : regarder en bas
    assert(out[1] > 0);
    // Incliné en arrière de 45° (écran vers le ciel à moitié) : le lacet suit toujours la verticale.
    double s = sqrt(0.5);
    gyro_turn(RT_BACKTAP_PORTRAIT, (double[3]){0, -s, -s}, (double[3]){0, s, s}, out);
    assert(fabs(out[0] + 10) < 1e-9 && fabs(out[1]) < 1e-9);
}

// L'axe horizontal de l'écran est celui de l'orientation de l'interface, quel que soit le côté vers lequel
// la gravité penche (couché sur le côté, elle tire vers le côté de l'écran : la prendre pour le bas
// ferait tourner le tangage autour du mauvais axe).
RT_CHECK(gyro_pitch_axis_follows_the_interface_orientation) {
    rt_gyro_params p = gyro_test_params();
    double out[2];
    for (int orient = -1; orient <= 1; orient += 2) {
        const double g[3] = {0.3 * orient, -0.9, -0.3};   // couché sur le côté, un peu en arrière
        assert(rt_gyro_delta(&p, (double[3]){0, orient, 0}, g, orient, 0.01, out));
        assert(fabs(out[1] + 10) < 1e-9);                  // 1 rad/s autour de l'axe horizontal de l'écran
    }
    // Portrait : x vers la droite, quelle que soit la gravité.
    const double g[3] = {-0.9, 0.3, -0.3};
    assert(rt_gyro_delta(&p, (double[3]){1, 0, 0}, g, RT_BACKTAP_PORTRAIT, 0.01, out));
    assert(fabs(out[1] + 10) < 1e-9);
}

// Grand écran du Duo (turn) : le repère de l'appareil est tourné d'un quart de tour dans le plan de l'écran
// (x' = -y, y' = x). Tenu en paysage, la gravité tire selon y, et l'axe horizontal de l'écran est x. Les
// mêmes sensations (lacet, tangage) que sur le petit écran, dans les deux paysages et en portrait.
RT_CHECK(gyro_wide_display_frame_is_turned_back) {
    rt_gyro_params p = gyro_test_params();
    p.turn = 1;
    double out[2];
    for (int orient = -1; orient <= 1; orient += 2) {
        const double g[3] = {0, -0.71 * orient, -0.7};   // paysage gauche (+1) : gravité vers -y ; droit : vers +y
        assert(rt_gyro_delta(&p, (double[3]){orient, 0, 0}, g, orient, 0.01, out));
        assert(fabs(out[1] + 10) < 1e-9 && fabs(out[0]) < 1e-9);   // haut de l'écran vers soi : regarder en haut
        assert(rt_gyro_delta(&p, (double[3]){0, 0.71 * orient, 0.7}, g, orient, 0.01, out));   // autour de la verticale
        assert(out[0] < -9 && fabs(out[1]) < 1e-9);               // du lacet vers la gauche, pas de tangage
    }
    // Portrait (gravité selon -x : celle d'un Duo déplié tenu droit) : le repère tourné redonne la gravité
    // selon -y, comme un iPhone droit.
    const double up_g[3] = {-0.96, 0, -0.28};
    assert(rt_gyro_delta(&p, (double[3]){1, 0, 0}, up_g, RT_BACKTAP_PORTRAIT, 0.01, out));    // tourner sur soi, vers la gauche
    assert(out[0] < -9 && fabs(out[1]) < 1e-9);
    assert(rt_gyro_delta(&p, (double[3]){0, -1, 0}, up_g, RT_BACKTAP_PORTRAIT, 0.01, out));   // haut de l'écran vers soi
    assert(fabs(out[1] + 10) < 1e-9 && fabs(out[0]) < 1e-9);
}

RT_CHECK(gyro_yaw_uses_the_real_vertical) {
    double out[2];
    // À plat écran vers le ciel : tourner sur la table, c'est tourner autour de z.
    gyro_turn(1, (double[3]){0, 0, -1}, (double[3]){0, 0, 1}, out);
    assert(out[0] < 0 && fabs(out[0] + 10) < 1e-9);
    // Incliné à 45° : seule la composante autour de la verticale compte.
    double s = sqrt(0.5);
    gyro_turn(1, (double[3]){s, 0, -s}, (double[3]){-s, 0, s}, out);
    assert(fabs(out[0] + 10) < 1e-9);
}

RT_CHECK(gyro_small_rotations_are_damped_and_gaps_ignored) {
    rt_gyro_params p = gyro_test_params();
    double out[2];
    const double g[3] = {1, 0, 0};
    // Au seuil : inchangé ; à la moitié : le quart ; à l'arrêt : rien.
    assert(rt_gyro_delta(&p, (double[3]){-0.05, 0, 0}, g, 1, 1, out) == 0);   // dt trop grand : trou
    assert(rt_gyro_delta(&p, (double[3]){-0.05, 0, 0}, g, 1, 0.1, out));
    assert(fabs(out[0] + 0.05 * 0.1 * 1000) < 1e-9);
    assert(rt_gyro_delta(&p, (double[3]){-0.025, 0, 0}, g, 1, 0.1, out));
    assert(fabs(out[0] + 0.025 * 0.5 * 0.1 * 1000) < 1e-9);
    assert(!rt_gyro_delta(&p, (double[3]){0, 0, 0}, g, 1, 0.01, out));
    // Orientation inconnue, gravité pas encore estimée, dt nul : rien.
    assert(!rt_gyro_delta(&p, (double[3]){-1, 0, 0}, g, 0, 0.01, out));
    assert(!rt_gyro_delta(&p, (double[3]){-1, 0, 0}, (double[3]){0, 0, 0}, 1, 0.01, out));
    assert(!rt_gyro_delta(&p, (double[3]){-1, 0, 0}, g, 1, 0, out));
}

RT_CHECK(gyro_settings_from_environment) {
    unsetenv("P2_GYRO"); unsetenv("P2_GYRO_SPEED"); unsetenv("P2_GYRO_TIGHTEN");
    assert(rt_gyro_enabled(1) && !rt_gyro_enabled(0));
    setenv("P2_GYRO", "0", 1);
    assert(!rt_gyro_enabled(1));
    setenv("P2_GYRO", "1", 1);
    assert(rt_gyro_enabled(0));
    rt_gyro_params p;
    rt_gyro_params_from_env(&p);
    assert(fabs(p.counts_per_rad - RT_GYRO_COUNTS_PER_RAD) < 1e-6 && fabs(p.tighten - 0.05) < 1e-12);
    setenv("P2_GYRO_SPEED", "2", 1); setenv("P2_GYRO_TIGHTEN", "0", 1);
    rt_gyro_params_from_env(&p);
    assert(fabs(p.counts_per_rad - 2 * RT_GYRO_COUNTS_PER_RAD) < 1e-6 && p.tighten == 0);
    unsetenv("P2_GYRO"); unsetenv("P2_GYRO_SPEED"); unsetenv("P2_GYRO_TIGHTEN");
}
