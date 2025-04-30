shader_type spatial;

#define SHADOW_REPLACE
#define HAS_BACKFACE

#include "res://addons/moonTerrain/shaders/mt_shader_base.gdshaderinc"

void fragment() {
	if (should_discard(FRAGCOORD.xy, VERTEX, CAMERA_POSITION_WORLD)) discard;
	ALBEDO = get_albedo(UV, FRONT_FACING);
}
