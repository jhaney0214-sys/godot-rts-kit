extends SceneTree
## Headless: order the demo's blue units across the long wall and report how
## far each ends from its slot after 20 seconds. A unit caught on a corner
## shows up here as a large distance.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var demo: Node = load("res://demo/demo.tscn").instantiate()
	root.add_child(demo)
	for i in 10:
		await physics_frame
	var sel: RTSSelection = demo.get_node("Selection")
	var target := Vector3(-5, 0, 30)
	sel.select(RTSKit.units(self, 0))
	sel.order_ground(target)
	for i in 1200:
		await physics_frame
	var worst := 0.0
	for u in RTSKit.units(self, 0):
		var d := RTSKit.flat_distance(u.global_position, target)
		worst = maxf(worst, d)
		print("%s at %s, %.1f from target, idle=%s" % [u.unit_type, u.global_position.snappedf(0.1), d, u.call("is_idle")])
	print("worst %.1f" % worst)
	quit(0 if worst < 8.0 else 1)
