extends SceneTree
## Frame time against unit count for four ways of moving many units in Godot 4.
##
## Run from the repository root (it opens a window: drawing is part of what is
## measured, so it cannot run headless):
##     godot --path . -s res://benchmark/bench.gd
##     godot --path . -s res://benchmark/bench.gd -- sizes=100,500 setups=flow_multimesh seconds=3
##
## Every unit walks to random points (or between four goals, for the flow
## field) on a 200 x 200 m map with eight walls, forever, so nothing goes idle.
## The camera looks down on the whole map, so every unit is drawn every frame.
## Vsync is off and the frame rate uncapped.
##
## Units move in _physics_process at 60 ticks a second, and uncapped frames run
## far faster than that, so most frames only draw. A game at 60 fps runs one
## tick in every frame, so the figure that matters is the time of a frame that
## includes one tick: `tick_frame_ms`. A frame with no tick is `draw_ms`, and
## the difference is what one simulation step of the units costs. Results go
## to the console and to benchmark/results/<date>.csv.

const AgentUnit := preload("res://benchmark/agent_unit.gd")
const SharedPath := preload("res://benchmark/shared_path.gd")
const FlowField := preload("res://benchmark/flow_field.gd")

const HALF := 100.0
const SPEED := 5.0
const WARMUP_TICKS := 180
const SETUPS := ["agent_avoid", "agent_plain", "shared_path", "flow_multimesh"]
const WALLS := [
	Rect2(-70, -70, 30, 6), Rect2(40, -70, 30, 6), Rect2(-70, 64, 30, 6), Rect2(40, 64, 30, 6),
	Rect2(-30, -30, 6, 60), Rect2(24, -30, 6, 60), Rect2(-10, -50, 20, 4), Rect2(-10, 46, 20, 4),
]

var sizes: Array[int] = [100, 250, 500, 1000, 2000]
var setups: Array = SETUPS.duplicate()
var seconds := 5.0
var shots := false
var _navmesh: NavigationMesh
var _unit_mesh: Mesh

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"sizes":
				sizes.clear()
				for s in kv[1].split(","):
					sizes.append(int(s))
			"setups":
				setups = Array(kv[1].split(","))
			"seconds":
				seconds = float(kv[1])
			"shots":
				shots = kv[1] == "1"
	_run.call_deferred()

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.6
	capsule.radial_segments = 8
	capsule.rings = 2
	_unit_mesh = capsule

	var machine := "%s | %s | Godot %s | %s" % [OS.get_processor_name(),
		RenderingServer.get_video_adapter_name(), Engine.get_version_info().string, OS.get_name()]
	var lines := PackedStringArray(["# " + machine,
		"# %s, %d s measured per run after %d warm-up ticks (60 a second), vsync off" % [
			Time.get_date_string_from_system(), int(seconds), WARMUP_TICKS],
		"setup,units,ticks,tick_frame_ms,tick_frame_p95_ms,draw_ms,step_ms,catchup_frames,catchup_ms,ticks_per_s"])
	print(lines[0])
	print(lines[2])
	for setup in setups:
		for n in sizes:
			var line := await _measure(setup, n)
			print(line)
			lines.append(line)
	var dir := "res://benchmark/results"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open("%s/%s.csv" % [dir, Time.get_date_string_from_system()], FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit(0)

func _arena() -> Node3D:
	var arena := Node3D.new()
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(HALF * 2.0, HALF * 2.0)
	ground.mesh = plane
	arena.add_child(ground)
	for r in WALLS:
		var wall := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(r.size.x, 3.0, r.size.y)
		wall.mesh = box
		wall.position = Vector3(r.position.x + r.size.x / 2.0, 1.5, r.position.y + r.size.y / 2.0)
		arena.add_child(wall)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 230, 0.01)
	camera.fov = 50.0
	camera.rotation_degrees = Vector3(-90, 0, 0)
	arena.add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
	arena.add_child(sun)
	var region := NavigationRegion3D.new()
	arena.add_child(region)
	root.add_child(arena)
	camera.make_current()
	if _navmesh == null:
		_navmesh = NavigationMesh.new()
		_navmesh.agent_radius = 0.5
		_navmesh.cell_size = 0.5
		var source := NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(_navmesh, source, arena)
		NavigationServer3D.bake_from_source_geometry_data(_navmesh, source)
	NavigationServer3D.map_set_cell_size(arena.get_world_3d().navigation_map, 0.5)
	region.navigation_mesh = _navmesh
	return arena

func _measure(setup: String, n: int) -> String:
	var arena := _arena()
	# A region set this frame is not on the map until the next sync, and until
	# then every closest-point query answers the origin.
	var map := arena.get_world_3d().navigation_map
	var synced := NavigationServer3D.map_get_iteration_id(map)
	var probe := Vector3(60, 0, 60)
	while (NavigationServer3D.map_get_iteration_id(map) == synced
			or NavigationServer3D.map_get_closest_point(map, probe).is_zero_approx()):
		await physics_frame
	match setup:
		"agent_avoid", "agent_plain":
			for i in n:
				var unit: Node3D = AgentUnit.new()
				unit.setup(_unit_mesh, setup == "agent_avoid", SPEED, i, HALF)
				arena.add_child(unit)
				unit.global_position = NavigationServer3D.map_get_closest_point(
					arena.get_world_3d().navigation_map,
					Vector3(randf_range(-HALF, HALF), 0.0, randf_range(-HALF, HALF)))
		"shared_path":
			var squads: Node3D = SharedPath.new()
			arena.add_child(squads)
			squads.setup(n, _unit_mesh, SPEED, n, HALF)
		"flow_multimesh":
			var flow: Node3D = FlowField.new()
			arena.add_child(flow)
			flow.setup(n, _unit_mesh, SPEED, n, HALF, WALLS)
		_:
			push_error("unknown setup %s" % setup)
	# Warm up in simulation time, not frames: at thousands of frames a second a
	# frame count would end before the units had moved.
	for i in WARMUP_TICKS:
		await physics_frame
	if shots:
		# Two pictures a second apart, to check by eye that units really move.
		for k in 2:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(
				"res://benchmark/results/shot-%s-%d-%d.png" % [setup, n, k]))
			if k == 0:
				await create_timer(1.0).timeout

	var with_tick := PackedFloat64Array()
	var draw_only := PackedFloat64Array()
	var catchup := PackedFloat64Array()
	var total_ticks := 0
	var start := Time.get_ticks_usec()
	var last := Time.get_ticks_usec()
	var end := last + int(seconds * 1e6)
	var ticks_before := Engine.get_physics_frames()
	while true:
		await process_frame
		var now := Time.get_ticks_usec()
		var ticks := Engine.get_physics_frames() - ticks_before
		var ms := (now - last) / 1000.0
		if ticks == 0:
			draw_only.append(ms)
		elif ticks == 1:
			with_tick.append(ms)
		else:
			# Two or more ticks in one frame: the simulation fell behind and
			# is catching up. Kept apart, and counted, since it means the
			# setup cannot hold 60 ticks a second at this size.
			catchup.append(ms)
		total_ticks += ticks
		last = now
		ticks_before = Engine.get_physics_frames()
		if now >= end:
			break
	arena.queue_free()
	await process_frame
	await process_frame

	var tick_mean := _mean(with_tick)
	var draw_mean := _mean(draw_only)
	var sorted := Array(with_tick)
	sorted.sort()
	var p95: float = sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))] if sorted.size() else NAN
	var elapsed := (Time.get_ticks_usec() - start) / 1e6
	return "%s,%d,%d,%.2f,%.2f,%.2f,%.2f,%d,%.2f,%.1f" % [setup, n, with_tick.size(), tick_mean, p95,
		draw_mean, tick_mean - draw_mean, catchup.size(), _mean(catchup), total_ticks / elapsed]

func _mean(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return NAN
	var total := 0.0
	for v in values:
		total += v
	return total / values.size()
