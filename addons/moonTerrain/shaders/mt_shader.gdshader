shader_type spatial;
render_mode cull_disabled, ensure_correct_normals;

//#define SHADOW_REPLACE

const float TEXTURE_BIAS = -3.0;

const vec3 DITHER_MAGIC = vec3(0.06711056, 0.00583715, 52.9829189);
const float DITHER_PLAYER_DISTANCE = 11.0;
const float DITHER_PLAYER_SHARPNESS = 4.0;
const float DITHER_DISTANCE_MIN = 2.5;
const float DITHER_DISTANCE_MAX = 5.0;
const float DITHER_PIXELIZE_MULT = 0.5;
const float DITHER_INV_PIXELIZE_MULT = 1.0 / DITHER_PIXELIZE_MULT; // do not change

uniform sampler2DArray surface_textures : repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec4 surface_uv_scales;

uniform sampler2D back_surface_texture : repeat_enable, filter_linear_mipmap_anisotropic;
uniform float back_surface_uv_scale;

uniform sampler2D shadow_gradient : repeat_disable, filter_linear;

global uniform vec3 player_world_position = vec3(0.0);
varying vec3 WORLD_VERTEX;

varying vec3 TRIPLANAR_POS;
varying vec3 POWER_NORMAL;

varying flat float SURFACE_IDX;
varying float SURFACE_UV_SCALE;

void vertex() {
	WORLD_VERTEX = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	SURFACE_IDX = UV.y;
	SURFACE_UV_SCALE = surface_uv_scales[int(SURFACE_IDX)];

	TANGENT = vec3(0.0, 0.0, -1.0) * abs(NORMAL.x);
	TANGENT += vec3(1.0, 0.0, 0.0) * abs(NORMAL.y);
	TANGENT += vec3(1.0, 0.0, 0.0) * abs(NORMAL.z);
	TANGENT = normalize(TANGENT);

	BINORMAL = vec3(0.0, 1.0, 0.0) * abs(NORMAL.x);
	BINORMAL += vec3(0.0, 0.0, -1.0) * abs(NORMAL.y);
	BINORMAL += vec3(0.0, 1.0, 0.0) * abs(NORMAL.z);
	BINORMAL = normalize(BINORMAL);

	// UV1 Triplanar: Enabled
	POWER_NORMAL = pow(abs(NORMAL), vec3(64.0));
	POWER_NORMAL /= dot(POWER_NORMAL, vec3(1.0));
	
	TRIPLANAR_POS = VERTEX;
	TRIPLANAR_POS *= vec3(1.0, -1.0, 1.0);
}

vec4 triplanar_texture_array(sampler2DArray p_sampler, vec3 p_weights, vec3 p_triplanar_pos) {
	vec4 samp = vec4(0.0);
	samp += texture(p_sampler, vec3(p_triplanar_pos.xy, SURFACE_IDX), TEXTURE_BIAS) * p_weights.z;
	samp += texture(p_sampler, vec3(p_triplanar_pos.xz, SURFACE_IDX), TEXTURE_BIAS) * p_weights.y;
	samp += texture(p_sampler, vec3(p_triplanar_pos.zy * vec2(-1.0, 1.0), SURFACE_IDX), TEXTURE_BIAS) * p_weights.x;
	return samp;
}

vec4 triplanar_texture(sampler2D p_sampler, vec3 p_weights, vec3 p_triplanar_pos) {
	vec4 samp = vec4(0.0);
	samp += texture(p_sampler, p_triplanar_pos.xy, TEXTURE_BIAS) * p_weights.z;
	samp += texture(p_sampler, p_triplanar_pos.xz, TEXTURE_BIAS) * p_weights.y;
	samp += texture(p_sampler, p_triplanar_pos.zy * vec2(-1.0, 1.0), TEXTURE_BIAS) * p_weights.x;
	return samp;
}

void fragment() {
	#ifdef SHADOW_REPLACE
	vec4 shadow_sample = texture(shadow_gradient, UV.x);
	ALBEDO = mix(
		triplanar_texture_array(surface_textures, POWER_NORMAL, TRIPLANAR_POS * SURFACE_UV_SCALE).rgb,
		shadow_sample.rgb,
		shadow_sample.a
	);
	#else
	ALBEDO = triplanar_texture_array(surface_textures, POWER_NORMAL, TRIPLANAR_POS * SURFACE_UV_SCALE).rgb
	* texture(shadow_gradient, UV).rgb;
	#endif
	
	// Apply backface texture
	ALBEDO = mix(ALBEDO, triplanar_texture(back_surface_texture, POWER_NORMAL, TRIPLANAR_POS * back_surface_uv_scale).rgb, float(!FRONT_FACING));
	
	// Terrain dither, also kills if backfacing is disabled
	float fade = 
		pow((1.0 - dot(normalize(WORLD_VERTEX - CAMERA_POSITION_WORLD), normalize(player_world_position - WORLD_VERTEX))) * DITHER_PLAYER_DISTANCE, DITHER_PLAYER_SHARPNESS)
		* clamp(smoothstep(DITHER_DISTANCE_MIN, DITHER_DISTANCE_MAX, length(VERTEX)), 0.0, 1.0);
	if (
		fade < 0.001
		|| fade < fract(
			DITHER_MAGIC.z
			* fract(
				dot(
					(round(FRAGCOORD * DITHER_PIXELIZE_MULT) * DITHER_INV_PIXELIZE_MULT).xy,
					DITHER_MAGIC.xy
				)
			)
		)
	) discard;
}
