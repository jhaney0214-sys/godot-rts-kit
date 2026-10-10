extends SceneTree
## Windowed only (nothing renders headless):
##   godot --path . --fixed-fps 60 -s tools/record_gif.gd
##   python tools/make_gif.py
## Loads the demo, drags a box over the blue units, orders them across the
## wall, and saves every fourth frame to export/frames/ (gitignored).
## make_gif.py turns those into docs/demo.gif.

const EVERY := 4
const OUT := "res://export/frames"

var _frame := 0
var _saved := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var demo: Node = load("res://demo/demo.tscn").instantiate()
	root.add_child(demo)
	var sel: RTSSelection = demo.get_node("Selection")
	var rig: RTSCameraRig = demo.get_node("CameraRig")
	rig.distance = 44.0
	for i in 30:
		rig.look_at_ground(_centre() + Vector3(4, 0, -6))
		await process_frame

	# The drag box, corner to corner around the units as they stand on screen.
	var box := Rect2(rig.screen_position(_centre()), Vector2.ZERO)
	for u in RTSKit.units(self, 0):
		box = box.expand(rig.screen_position(u.global_position))
	box = box.grow(36.0)
	for i in 20:
		await _step()
	sel._unhandled_input(_button(MOUSE_BUTTON_LEFT, true, box.position))
	for i in 36:
		var motion := InputEventMouseMotion.new()
		motion.position = box.position.lerp(box.end, (i + 1) / 36.0)
		sel._unhandled_input(motion)
		await _step()
	sel._unhandled_input(_button(MOUSE_BUTTON_LEFT, false, box.end))
	for i in 24:
		await _step()

	sel.order_ground(Vector3(-5, 0, 30))
	for i in 340:
		rig.look_at_ground(_centre() + Vector3(4, 0, -6))
		await _step()
	print("saved %d frames to export/frames" % _saved)
	quit()

func _centre() -> Vector3:
	var mine := RTSKit.units(self, 0)
	var centre := Vector3.ZERO
	for u in mine:
		centre += u.global_position
	return centre / float(mine.size())

func _button(index: MouseButton, pressed: bool, at: Vector2) -> InputEventMouseButton:
	var button := InputEventMouseButton.new()
	button.button_index = index
	button.pressed = pressed
	button.position = at
	return button

func _step() -> void:
	await process_frame
	_frame += 1
	if _frame % EVERY == 0:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%04d.png" % [OUT, _saved])
		_saved += 1
