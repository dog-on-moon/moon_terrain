@tool
extends Node3D
class_name MTBase3D
## The base class for 3D moonTerrain classes.

## Debug variable to view nodes in editor.
## Preferably keep this false (only set to true for testing/debugging)
const VIEW_NODES_IN_EDITOR := false

## The material used for creating the MT mesh.
@export var material: MTMaterial:
	set(x):
		if material:
			material.render_changed.disconnect(update)
		material = x
		if material:
			material.render_changed.connect(update)
		update()

## The bottom height that the mesh is generated to.
@export var flatten_height := -32.0:
	set(x):
		flatten_height = x
		update()

## Determines if the mesh is only generated in the editor.
## (Using MTBaker is recommended for runtime performance.)
@export var editor_only := true

var mesh_instance_3d: MeshInstance3D = null
var static_body_3d: StaticBody3D = null
var collision_shape_3d: CollisionShape3D = null

func _ready() -> void:
	if Engine.is_editor_hint() or not editor_only:
		set_notify_transform(true)
		update()

func update():
	if not Engine.is_editor_hint() and editor_only:
		return
	if not material:
		return
	if not is_node_ready():
		return
	
	for child in get_children():
		remove_child(child)
		child.queue_free()
	mesh_instance_3d = null
	static_body_3d = null
	collision_shape_3d = null
	
	if not mesh_instance_3d:
		mesh_instance_3d = MeshInstance3D.new()
		add_child(mesh_instance_3d)
		if VIEW_NODES_IN_EDITOR:
			mesh_instance_3d.owner = get_tree().edited_scene_root
			mesh_instance_3d.name = "MeshInstance3D"
	
	if not static_body_3d:
		static_body_3d = StaticBody3D.new()
		static_body_3d.set_script(material.collision_script)
		add_child(static_body_3d)
		if VIEW_NODES_IN_EDITOR:
			static_body_3d.owner = get_tree().edited_scene_root
			static_body_3d.name = "StaticBody3D"
	
	if not collision_shape_3d:
		collision_shape_3d = CollisionShape3D.new()
		static_body_3d.add_child(collision_shape_3d)
		if VIEW_NODES_IN_EDITOR:
			collision_shape_3d.owner = get_tree().edited_scene_root
			collision_shape_3d.name = "CollisionShape3D"
	
	mesh_instance_3d.mesh = _generate_mesh()
	collision_shape_3d.shape = null
	
	if _collision_is_valid():
		var collision_mesh := MeshInstance3D.new()
		collision_mesh.mesh = _generate_collision_mesh()
		if collision_mesh.mesh:
			collision_mesh.create_trimesh_collision()
			if collision_mesh.get_child_count() and collision_mesh.get_child(0).get_child_count():
				var cs3d: CollisionShape3D = collision_mesh.get_child(0).get_child(0)
				collision_shape_3d.shape = cs3d.shape
		collision_mesh.queue_free()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		update.call_deferred()

## virtual override
func _generate_mesh() -> Mesh:
	return null

## virtual override
func _generate_collision_mesh() -> Mesh:
	return null

## virtual override
func _get_duplicate_check() -> Variant:
	return null

## virtual override
func _handle_duplicate():
	pass

## virtual override
func _collision_is_valid() -> bool:
	return true

func get_flatten_height() -> float:
	return flatten_height - transform.origin.y

#region Dupe Check

## A cache for handling existing MTBase3Ds.
static var EDITOR_MT_CACHE: Dictionary[MTBase3D, Resource] = {}

func _enter_tree() -> void:
	if Engine.is_editor_hint():
		_check_dupe()

func _check_dupe():
	if Engine.is_editor_hint():
		var check := _get_duplicate_check()
		if not check:
			EDITOR_MT_CACHE.erase(self)
		else:
			for mt in EDITOR_MT_CACHE:
				if mt == self:
					continue
				if mt._get_duplicate_check() == check:
					_handle_duplicate()
					break
			EDITOR_MT_CACHE[self] = check

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		EDITOR_MT_CACHE.erase(self)

#endregion
