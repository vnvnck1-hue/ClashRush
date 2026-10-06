shader_type spatial;
// Additive FX (hot cores, flashes, beams).
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled, fog_disabled;
#include "res://scripts/fx_cartoon.gdshaderinc"
