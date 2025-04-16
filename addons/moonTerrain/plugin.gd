@tool
extends EditorPlugin

var mt_brush_3d_gizmo_plugin = MTBrush3DGizmoPlugin.new()
var mt_path_3d_gizmo_plugin = MTPath3DGizmoPlugin.new()

func _enter_tree():
	mt_brush_3d_gizmo_plugin.plugin = self
	add_node_3d_gizmo_plugin(mt_brush_3d_gizmo_plugin)
	mt_path_3d_gizmo_plugin.plugin = self
	add_node_3d_gizmo_plugin(mt_path_3d_gizmo_plugin)

func _exit_tree():
	remove_node_3d_gizmo_plugin(mt_brush_3d_gizmo_plugin)
	remove_node_3d_gizmo_plugin(mt_path_3d_gizmo_plugin)
