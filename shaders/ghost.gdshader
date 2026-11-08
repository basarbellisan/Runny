// Hayalet (tasarım çalışması): yarı saydam ince örtü. Kenarlarda (kumaşa yandan bakılan yerde)
// daha opak, ortada saydam; etek uçları dalgalanır, geriye savrulur. Ağ dönel bir profilden
// kurulur: UV.x = açı (0.5 ön, kameraya bakan; dikiş arkada), UV.y = yükseklik (0 etek ucu, 1 tepe).
// Dış yüz (ön): iç yüzden sonra çizilir (saydam katmanlar karışıp çizgilenmesin)
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_disabled, shadows_disabled;
#include "res://shaders/ghost.gdshaderinc"
