render_mode cull_disabled;

// #define SHADOW_REPLACE

const float TEXTURE_BIAS = -3.0;
const float TRIPLANAR_SHARPNESS = 64.0;

uniform sampler2D albedo_texture : repeat_enable, filter_linear_mipmap_anisotropic;
uniform float uv_scale;
uniform sampler2D backface_albedo_texture : repeat_enable, filter_linear_mipmap_anisotropic;
uniform float backface_uv_scale;
uniform sampler2D shadow_gradient : repeat_disable, filter_linear;

varying vec3 WORLD_VERTEX;
varying vec2 TRIPLANAR_UV;

void vertex() {
	WORLD_VERTEX = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	vec3 v = abs(NORMAL);
	v = (1.0 - abs(sign(v - vec3(max(max(v.x, v.y), v.z))))) * vec3(1, 2, 3);
	TRIPLANAR_UV = mat3(
		vec3(-VERTEX.z, -VERTEX.y, 0.0),
		vec3(VERTEX.x, -VERTEX.z, 0.0),
		vec3(VERTEX.x, -VERTEX.y, 0.0)
	)[int(max(max(v.x, v.y), v.z) - 1.0)].xy;
}

vec3 get_albedo(vec2 uv, bool front_facing) {
	// Base texture sample
	vec3 albedo = texture(albedo_texture, TRIPLANAR_UV * uv_scale, TEXTURE_BIAS).rgb;
	
	// Texture shadow
	#ifdef SHADOW_REPLACE
		albedo = mix(albedo, texture(shadow_gradient, uv).rgb, uv.x);
	#else
		albedo *= texture(shadow_gradient, uv).rgb;
	#endif
	
	// Backface
	albedo = mix(
		albedo,
		texture(backface_albedo_texture, TRIPLANAR_UV * backface_uv_scale, TEXTURE_BIAS).rgb,
		float(!front_facing)
	);
	
	return albedo;
}

global uniform vec3 player_world_position;

const vec3 DITHER_MAGIC = vec3(0.06711056, 0.00583715, 52.9829189);
const float DITHER_PLAYER_DISTANCE = 11.0;
const float DITHER_PLAYER_SHARPNESS = 6.0;
const float DITHER_DISTANCE_MIN = 2.5;
const float DITHER_DISTANCE_MAX = 5.0;
const float DITHER_PIXELIZE_MULT = 0.5;
const float DITHER_INV_PIXELIZE_MULT = 1.0 / DITHER_PIXELIZE_MULT; // do not change

// Determines if our current fragment should discard.
// ( deferred to another function due to shader include bugs )
bool should_discard(vec2 fragcoord, vec3 vertex, vec3 camera_position_world) {
	float fade = 
		pow((1.0 - dot(normalize(WORLD_VERTEX - camera_position_world), normalize(player_world_position - WORLD_VERTEX))) * DITHER_PLAYER_DISTANCE, DITHER_PLAYER_SHARPNESS)
		* clamp(smoothstep(DITHER_DISTANCE_MIN, DITHER_DISTANCE_MAX, length(vertex)), 0.0, 1.0);
	return (
		fade < 0.001
		|| fade < fract(
			DITHER_MAGIC.z
			* fract(
				dot(
					round(fragcoord * DITHER_PIXELIZE_MULT) * DITHER_INV_PIXELIZE_MULT,
					DITHER_MAGIC.xy
				)
			)
		)
	);
}
