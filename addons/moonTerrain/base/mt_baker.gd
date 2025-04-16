@tool
extends Node3D
class_name MTBaker
## Bakes MTCSG children into a separate scene.

@export_tool_button("Bake MTCSG Descendents") var _bake = bake

## The save path of the bake scene.
## If empty, it is determined automatically.
@export_file("*.tscn") var baked_scene_path := ""

## Descendent path to the baked scene.
@export var baked_scene: Node = null

func _enter_tree() -> void:
	if not Engine.is_editor_hint() and baked_scene_path and can_load_baked_mesh():
		# Remove placeholder node.
		if baked_scene:
			baked_scene.get_parent().remove_child(baked_scene)
			baked_scene.queue_free()
		
		# Add new baked scene from load.
		baked_scene = load(baked_scene_path).instantiate()
		add_child(baked_scene)
		baked_scene.name = "MTBaked"

func bake(): 
	## Determine baked scene path.
	if not baked_scene_path:
		if not get_bake_scene_path():
			print('Bake failed (destination unspecified and could not be determined)')
			return
		
		var dialog := ConfirmationDialog.new()
		dialog.title = "Bake Destination"
		dialog.dialog_text = "The baked scene will be saved here:\n\n'%s'\n\nPress OK to confirm." % get_bake_scene_path()
		EditorInterface.popup_dialog_centered(dialog)
		dialog.confirmed.connect(func ():
			baked_scene_path = get_bake_scene_path()
			bake.call_deferred()
		)
		return
	
	# Remove old baked scene.
	if baked_scene:
		baked_scene.get_parent().remove_child(baked_scene)
		baked_scene.queue_free()
		baked_scene = null
	
	# Setup new baked scene.
	baked_scene = Node3D.new()
	add_child(baked_scene)
	baked_scene.name = "MTBaked"
	
	# Setup bake heirarchy.
	var material_to_mt: Dictionary[MTMaterial, Array] = {}
	for mt in get_mt_nodes(self):
		material_to_mt.get_or_add(mt.material, []).append(mt)
	
	## Setup mesh bake.
	var root_csg := CSGCombiner3D.new()
	for material in material_to_mt:
		## Setup mesh CSG.
		var mesh_csg := CSGCombiner3D.new()
		for mt: MTBase3D in material_to_mt[material]:
			var mt_csg := CSGMesh3D.new()
			mt_csg.mesh = mt._generate_mesh()
			mesh_csg.add_child(mt_csg)
			mt_csg.transform = mt.global_transform
		root_csg.add_child(mesh_csg)
	
	await get_tree().process_frame
	
	var mesh_instance_3d := MeshInstance3D.new()
	mesh_instance_3d.mesh = root_csg.bake_static_mesh()
	mesh_instance_3d.mesh.lightmap_unwrap(Transform3D.IDENTITY, 1.0 / 16.0)
	baked_scene.add_child(mesh_instance_3d)
	mesh_instance_3d.name = "MeshInstance3D"
	mesh_instance_3d.owner = baked_scene
	root_csg.queue_free()
	
	for surf_idx in mesh_instance_3d.mesh.get_surface_count():
		var s := mesh_instance_3d.mesh.surface_get_material(surf_idx)
		if s and (not s.resource_path or not FileAccess.file_exists(s.resource_path)):
			push_warning("Generated mesh surface idx %s using non-external resource, this incurs a performance penalty." % surf_idx)
	
	## Setup collision bake.
	for material in material_to_mt:
		## Setup collision CSG.
		var collision_csg := CSGCombiner3D.new()
		for mt: MTBase3D in material_to_mt[material]:
			var mt_csg := CSGMesh3D.new()
			mt_csg.mesh = mt._generate_collision_mesh()
			collision_csg.add_child(mt_csg)
			mt_csg.transform = mt.global_transform
		
		await get_tree().process_frame
		
		## Setup material collision.
		var material_body := StaticBody3D.new()
		material_body.script = material.collision_script
		
		var material_cs3d := CollisionShape3D.new()
		material_cs3d.shape = collision_csg.bake_collision_shape()
		material_body.add_child(material_cs3d)
		material_cs3d.name = "CollisionShape3D"
		
		baked_scene.add_child(material_body)
		material_body.name = material.name.to_pascal_case() + "Body"
		material_cs3d.owner = baked_scene
		material_body.owner = baked_scene
		
		## Remove collision CSG.
		collision_csg.queue_free()
	
	# Finalize bake.
	var packed_scene := PackedScene.new()
	var error := packed_scene.pack(baked_scene)
	if error != OK:
		print('Baking failed (%s).' % error_string(error))
		baked_scene.queue_free()
		baked_scene = null
	else:
		if FileAccess.file_exists(baked_scene_path):
			error = OS.move_to_trash(ProjectSettings.globalize_path(baked_scene_path))
		if error != OK:
			print('Cleanup failed (%s).' % error_string(error))
			baked_scene.queue_free()
			baked_scene = null
		else:
			error = ResourceSaver.save(packed_scene, baked_scene_path)
			if error != OK:
				print('Saving failed (%s).' % error_string(error))
				baked_scene.queue_free()
				baked_scene = null
			else:
				print('Bake success.')
				baked_scene.owner = owner
				baked_scene.scene_file_path = baked_scene_path
				baked_scene.set_scene_instance_load_placeholder(true)
				baked_scene.visible = false

static func get_mt_nodes(root: Node) -> Array[MTBase3D]:
	var a: Array[MTBase3D] = []
	for child in root.get_children():
		if is_instance_of(child, MTBase3D):
			a.append(child)
		a.append_array(get_mt_nodes(child))
	return a

func can_load_baked_mesh() -> bool:
	return true

func get_bake_scene_path() -> String:
	var base_path := get_tree().edited_scene_root.scene_file_path
	var bake_path := base_path.get_basename() + "_MT.tscn"
	return bake_path
