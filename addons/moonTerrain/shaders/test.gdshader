shader_type spatial;

#define TRIPLANAR
#define HAS_SHADOW

#include "res://addons/moonTerrain/shaders/mt_shader_base.gdshaderinc"

void fragment() {
	ALBEDO = get_albedo(UV, FRONT_FACING);
	if (should_discard(FRAGCOORD.xy, VERTEX, CAMERA_POSITION_WORLD)) discard;
}
