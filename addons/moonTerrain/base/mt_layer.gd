@tool
extends Resource
class_name MTLayer
## A generated material layer within a MTMaterial.

signal render_changed

## The generation mode of this layer.
enum Mode {
	FLOOR = 0,  ## Generates a flat floor.
	WALL = 2,   ## Generates a wall.
	ROOF = 1,   ## Generates a flat ceiling.
}

## The way this layer generates.
@export var generation_mode := Mode.FLOOR:
	set(x):
		generation_mode = x
		notify_property_list_changed()
		render_changed.emit()

@export_group("Visual")
## The texture of a MTSurface.
@export var texture: Texture2D:
	set(x):
		if texture:
			texture.changed.disconnect(render_changed.emit)
		texture = x
		if texture:
			texture.changed.connect(render_changed.emit)
		render_changed.emit()

## The UV scale of the surface.
@export_range(0.01, 4.0, 0.001, "or_greater") var uv_scale := 1.0:
	set(x):
		uv_scale = x
		render_changed.emit()

enum ShadowMode {
	Multiply,		## The shadow color is multiplied with the base texture.
	Replace,		## The shadow color replaces the base texture.
}

## Controls how shading is applied onto the layer texture.
@export var shadow_mode := ShadowMode.Multiply:
	set(x):
		shadow_mode = x
		render_changed.emit()

## The material used for rendering this layer.
## Its properties are auto-generated, however, you should
## save it externally to the filesystem for baked meshes
## to reference
@export var material := ShaderMaterial.new():
	set(x):
		if not x:
			x = ShaderMaterial.new()
		material = x
		render_changed.emit()

@export_group("Build")
## How far this layer expands outwards.
@export var expand := 0.0:
	set(x):
		expand = x
		render_changed.emit()

## The height of the layer.
@export var height := 0.0:
	set(x):
		height = x
		render_changed.emit()

## Determines if this layer is "flattened", building down to a certain height.
## The flattened height is specified externally.
## Use for low wall layers and roofs.
@export var flatten := false:
	set(x):
		flatten = x
		render_changed.emit()

@export_group("Shadow")
## The shadow gradient end sample of the layer.
@export var shadow := 0.0:
	set(x):
		shadow = x
		render_changed.emit()

## Determines if this layer should have a separate shadow start parameter.
## Otherwise, the shading of the previous layer is inherited.
@export var override_start_shadow := false:
	set(x):
		override_start_shadow = x
		notify_property_list_changed()
		render_changed.emit()

## The shadow gradient start sample of the layer.
@export var start_shadow := 0.0:
	set(x):
		start_shadow = x
		if override_start_shadow:
			render_changed.emit()

## Generates a layer on the MTMesher.
func create_layer(mt3d: MTBase3D, curve: Curve3D, material: MTMaterial, mesher: MTMesher):
	# mt3d, curve, self, state
	if curve.point_count <= 2:
		return
	match generation_mode:
		Mode.FLOOR:
			mesher.build_floor(mt3d, curve, material, self, false)
		Mode.ROOF:
			mesher.build_floor(mt3d, curve, material, self, true)
		Mode.WALL:
			mesher.build_wall(mt3d, curve, material, self)
		_:
			assert(false)
			
const VARIANT_00 = preload("res://addons/moonTerrain/shaders/variant_00.gdshader")
const VARIANT_01 = preload("res://addons/moonTerrain/shaders/variant_01.gdshader")
const VARIANT_10 = preload("res://addons/moonTerrain/shaders/variant_10.gdshader")
const VARIANT_11 = preload("res://addons/moonTerrain/shaders/variant_11.gdshader")

func update_shader_parameters(mtmaterial: MTMaterial):
	_update_name()
	
	# Update the current shader.
	if shadow_mode == ShadowMode.Replace:
		if mtmaterial.backface_texture:
			material.shader = VARIANT_11
		else:
			material.shader = VARIANT_10
	else:
		if mtmaterial.backface_texture:
			material.shader = VARIANT_01
		else:
			material.shader = VARIANT_00
	
	# Update shader parameters.
	material.set_shader_parameter(&"albedo_texture", texture)
	material.set_shader_parameter(&"uv_scale", uv_scale)
	if mtmaterial.backface_texture:
		material.set_shader_parameter(&"backface_albedo_texture", mtmaterial.backface_texture)
		material.set_shader_parameter(&"backface_uv_scale", mtmaterial.backface_uv_scale)
	material.set_shader_parameter(&"shadow_gradient", mtmaterial.shadow_gradient_texture)

func _validate_property(property: Dictionary) -> void:
	if Engine.is_editor_hint():
		var n: StringName = property.name
		if not override_start_shadow and n == &"start_shadow":
			property.usage ^= PROPERTY_USAGE_EDITOR

func _update_name():
	if not Engine.is_editor_hint():
		return
	var title := {
		Mode.FLOOR: "Floor",
		Mode.WALL: "Wall",
		Mode.ROOF: "Roof",
	}.get(generation_mode, "")
	var _height := ""
	if height or flatten:
		_height = " (%s h)" % snappedf(height, 0.1) if not flatten else " (flat)"
	resource_name = title + _height
