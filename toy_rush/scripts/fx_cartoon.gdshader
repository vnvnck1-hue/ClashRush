shader_type spatial;
// Cel cut-out FX (smoke, shards, slashes, decals): alpha-scissor = opaque pass, hard edges, no sorting issues.
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled, fog_disabled;
#define CUTOUT
#include "res://scripts/fx_cartoon.gdshaderinc"
