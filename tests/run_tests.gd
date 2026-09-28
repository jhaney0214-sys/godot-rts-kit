extends SceneTree
## Headless tests for the RTS Kit.
##
##   godot --headless --path . --import          (once, on a fresh checkout)
##   godot --headless --path . -s tests/run_tests.gd
##
## Exits 1 on any failure. EXPECTED_CHECKS guards against a runtime error
## quietly ending a test early: GDScript aborts the function without failing
## anything, so the count is what notices.

const EXPECTED_CHECKS := 29

var _checks: int = 0
var _failures: int = 0

class StubUnit extends Node3D:
	var team: int = 0
	var vision_radius: float = 0.0
	var unit_type: String = "stub"
	var is_selected: bool = false
	var moves: Array = []
	var attacked: Node3D = null
	func _init(t: int = 0, at: Vector3 = Vector3.ZERO, sight: float = 0.0) -> void:
		team = t
		position = at
		vision_radius = sight
		add_to_group(RTSKit.UNIT_GROUP)
	func rts_set_selected(on: bool) -> void:
		is_selected = on
	func rts_move(point: Vector3, queued: bool) -> void:
		moves.append([point, queued])
	func rts_attack(target: Node3D) -> void:
		attacked = target

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, name: String) -> void:
	_checks += 1
	if ok:
		print("PASS  ", name)
	else:
		_failures += 1
		print("FAIL  ", name)

func _run() -> void:
	_test_formation()
	_test_nav_routes_around_a_wall()
	_test_nav_unreachable()
	await _test_nav_bake()
	await _test_fog()
	await _test_selection()
	if _checks != EXPECTED_CHECKS:
		_failures += 1
		print("FAIL  ran %d checks, expected %d - a test ended early" % [_checks, EXPECTED_CHECKS])
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

func _clear() -> void:
	for child in root.get_children():
		child.queue_free()

# ------------------------------------------------------------ formation

func _test_formation() -> void:
	var slots := RTSKit.formation(Vector3(10, 0, 10), 7, 3.0)
	check(slots.size() == 7, "formation gives one slot per unit")
	var unique := {}
	for s in slots:
		unique[Vector2(snappedf(s.x, 0.01), snappedf(s.z, 0.01))] = true
	check(unique.size() == 7, "formation slots are all different")
	var sum := Vector3.ZERO
	for s in slots:
		sum += s
	check((sum / 7.0).distance_to(Vector3(10, 0, 10)) < 3.0, "formation is centred near the ordered point")

# ------------------------------------------------------------ navigation

func _wall_grid() -> RTSNavGrid:
	# A wall down x = 0 from z = -30 to the far edge; the gap is at z < -30.
	var grid := RTSNavGrid.new(Rect2(-50, -50, 100, 100), 2.0)
	grid.block_rect(Rect2(-2, -30, 4, 80))
	return grid

func _test_nav_routes_around_a_wall() -> void:
	var grid := _wall_grid()
	var from := Vector3(-20, 0, 20)
	var to := Vector3(20, 0, 20)
	check(not grid.walkable(from, to), "a straight line through the wall is not walkable")
	var path := grid.route(from, to)
	check(path.size() >= 2 and path[path.size() - 1] == to, "route ends at the destination")
	var ok := true
	var prev := from
	var lowest := INF
	for p in path:
		ok = ok and grid.walkable(prev, p)
		lowest = minf(lowest, p.z)
		prev = p
	check(ok, "every leg of the route is walkable")
	check(lowest < -28.0, "the route goes round through the gap")
	check(path.size() <= 4, "route is pulled tight (%d waypoints)" % path.size())
	var open := grid.route(Vector3(10, 0, 0), Vector3(30, 0, 5))
	check(open.size() == 1, "open ground is one straight leg")

func _test_nav_unreachable() -> void:
	var grid := RTSNavGrid.new(Rect2(-50, -50, 100, 100), 2.0)
	# A closed box around (20, 20).
	grid.block_rect(Rect2(10, 10, 20, 2))
	grid.block_rect(Rect2(10, 28, 20, 2))
	grid.block_rect(Rect2(10, 10, 2, 20))
	grid.block_rect(Rect2(28, 10, 2, 20))
	var to := Vector3(20, 0, 20)
	var path := grid.route(Vector3(-20, 0, -20), to)
	check(path.size() > 0 and path[path.size() - 1] != to, "an enclosed goal ends at the nearest reachable point")
	var into_wall := grid.route(Vector3(-20, 0, -20), Vector3(11, 0, 20))
	check(into_wall.size() > 0 and not grid.is_blocked(into_wall[into_wall.size() - 1]), "a goal inside a wall ends on open ground")

func _test_nav_bake() -> void:
	_clear()
	var body := StaticBody3D.new()
	body.collision_layer = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 4, 10)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, 2, 0)
	root.add_child(body)
	await physics_frame
	await physics_frame
	var grid := RTSNavGrid.new(Rect2(-20, -20, 40, 40), 2.0)
	var solid := grid.bake_from_physics(root.world_3d, 2, 0.5)
	check(grid.is_blocked(Vector3(0, 0, 0)), "baking marks cells under a collider solid")
	check(not grid.is_blocked(Vector3(15, 0, 15)), "baking leaves open ground open")
	check(solid > 0 and solid < 100, "baked solid count is plausible (%d)" % solid)

# ------------------------------------------------------------ fog

func _test_fog() -> void:
	_clear()
	await process_frame
	var scout := StubUnit.new(0, Vector3(0, 0, 0), 10.0)
	root.add_child(scout)
	var near_enemy := StubUnit.new(1, Vector3(5, 0, 0))
	var far_enemy := StubUnit.new(1, Vector3(-40, 0, -40))
	root.add_child(near_enemy)
	root.add_child(far_enemy)
	var fog := RTSFogOfWar.new()
	fog.world_rect = Rect2(-50, -50, 100, 100)
	fog.resolution = 128
	root.add_child(fog)
	fog.refresh()
	check(fog.visible_at(Vector3(0, 0, 0)), "ground under a unit is visible")
	check(not fog.visible_at(Vector3(30, 0, 30)), "ground far from every unit is not visible")
	check(near_enemy.visible and not far_enemy.visible, "enemies show inside vision and hide outside it")
	scout.position = Vector3(30, 0, 30)
	fog.refresh()
	check(fog.explored_at(Vector3(0, 0, 0)) and not fog.visible_at(Vector3(0, 0, 0)), "ground you left is remembered, not watched")
	check(not fog.explored_at(Vector3(-40, 0, 40)), "ground nobody went near is unexplored")
	check(not near_enemy.visible, "an enemy you stopped watching is hidden again")

# ------------------------------------------------------------ selection

func _test_selection() -> void:
	_clear()
	await process_frame
	var rig := RTSCameraRig.new()
	rig.bounds = Rect2()
	root.add_child(rig)
	var sel := RTSSelection.new()
	sel.camera_rig = rig
	root.add_child(sel)
	var a := StubUnit.new(0, Vector3(-3, 0, 0))
	var b := StubUnit.new(0, Vector3(3, 0, 0))
	var enemy := StubUnit.new(1, Vector3(0, 0, -4))
	root.add_child(a)
	root.add_child(b)
	root.add_child(enemy)
	await process_frame

	var screen := root.get_visible_rect()
	sel.select_in_screen_rect(screen)
	check(sel.selected.size() == 2 and a.is_selected and b.is_selected, "a box over the screen selects your units only")

	sel.select_at_screen(rig.screen_position(a.global_position))
	check(sel.selected == [a] and not b.is_selected, "a click selects just that unit and clears the rest")

	sel.select_at_screen(rig.screen_position(b.global_position), true)
	check(sel.selected.size() == 2, "shift-click adds to the selection")

	sel.select_at_screen(rig.screen_position(enemy.global_position))
	check(sel.selected.is_empty(), "clicking an enemy does not select it")

	sel.select([a, b])
	sel.assign_group(0)
	sel.clear()
	sel.recall_group(0)
	check(sel.selected.size() == 2, "a control group recalls what was saved")

	sel.order_ground(Vector3(20, 0, 20))
	var ta: Vector3 = a.moves[-1][0]
	var tb: Vector3 = b.moves[-1][0]
	check(ta != tb and RTSKit.flat_distance(ta, Vector3(20, 0, 20)) < 4.0, "a group order spreads units into formation")

	sel.order_ground(Vector3(0, 0, 30), null, true)
	check(a.moves[-1][1] == true, "shift orders are passed on as queued")

	sel.order_at_screen(rig.screen_position(enemy.global_position))
	check(a.attacked == enemy and b.attacked == enemy, "right-clicking an enemy orders an attack")

	var ground := rig.ground_at(rig.screen_position(Vector3(7, 0, -5)))
	check(ground.distance_to(Vector3(7, 0, -5)) < 0.1, "ground_at inverts screen_position on flat ground")
