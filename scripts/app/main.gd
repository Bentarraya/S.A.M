extends Node3D

func _ready() -> void:
	var light := DirectionalLight3D.new()
	light.shadow_enabled = false
	light.rotation_degrees = Vector3(-60, -30, 0)
	add_child(light)
	var cam := Camera3D.new()
	cam.position = Vector3(18, 24, 20)
	add_child(cam)
	cam.look_at(Vector3(18, 0, 4))
