// Hayalet örtüsünün iç yüzü: önce bu çizilir, sonra dış yüz (ghost.gdshader) üstüne
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_front, diffuse_burley, specular_disabled, shadows_disabled;
#define BACK_FACE
#include "res://shaders/ghost.gdshaderinc"
