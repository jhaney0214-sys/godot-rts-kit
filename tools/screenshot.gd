extends SceneTree
## Windowed only (nothing renders headless):
##   godot --path . -s tools/screenshot.gd
## Loads the demo, selects the blue units, orders them across the wall, and
## saves docs/screenshot.png once they are on their way.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var demo: Node = load("res://demo/demo.tscn").instantiate()
	root.add_child(demo)
	for i in 30:
		await process_frame
	var sel: RTSSelection = demo.get_node("Selection")
	sel.select(RTSKit.units(self, 0))
	sel.order_ground(Vector3(-5, 0, 30))
	var rig: RTSCameraRig = demo.get_node("CameraRig")
	rig.distance = 58.0
	for i in 330:
		var mine := RTSKit.units(self, 0)
		var centre := Vector3.ZERO
		for u in mine:
			centre += u.global_position
		rig.look_at_ground(centre / float(mine.size()) + Vector3(4, 0, -6))
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/screenshot.png")
	print("saved docs/screenshot.png")
	quit()
