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
##
## `mode=ceiling` answers the other question: the most units each setup holds
## at 60 fps and at 30 fps. For a target of F fps the simulation runs at F
## steps a second (a 30 fps game steps 30 times a second), and a size "holds"
## when the 95th-percentile frame that ran one step is under 1000/F ms, at
## most 1% of steps fell in catch-up frames, and the simulation kept at least
## 98% of its F steps a second (see _holds). It doubles the count from
## `start` until a size fails, then halves the gap until it is within 5%, and
## writes every size it tried to benchmark/results/ceiling-<date>T<time>.csv:
##     godot --path . -s res://benchmark/bench.gd -- mode=ceiling
##     godot --path . -s res://benchmark/bench.gd -- mode=ceiling fps=60 setups=flow_multimesh

const AgentUnit := preload("res://benchmark/agent_unit.gd")
const SharedPath := preload("res://benchmark/shared_path.gd")
const FlowField := preload("res://benchmark/flow_field.gd")

const HALF := 100.0
const SPEED := 5.0
const WARMUP_SECONDS := 3
const HOLD_RATE := 0.98
const SETUPS := ["agent_avoid", "agent_plain", "shared_path", "flow_multimesh"]
const WALLS := [
	Rect2(-70, -70, 30, 6), Rect2(40, -70, 30, 6), Rect2(-70, 64, 30, 6), Rect2(40, 64, 30, 6),
	Rect2(-30, -30, 6, 60), Rect2(24, -30, 6, 60), Rect2(-10, -50, 20, 4), Rect2(-10, 46, 20, 4),
]

var sizes: Array[int] = [100, 250, 500, 1000, 2000]
var setups: Array = SETUPS.duplicate()
var seconds := 5.0
var shots := false
var mode := "sweep"
var targets: Array[int] = [60, 30]
var start_size := 500
var max_size := 64000
var _rate := 60
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
			"mode":
				mode = kv[1]
			"fps":
				targets.clear()
				for s in kv[1].split(","):
					targets.append(int(s))
			"start":
				start_size = int(kv[1])
			"max":
				max_size = int(kv[1])
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

	var machine := "%s, %d threads, %d GB RAM | %s | %s %s, %s | Godot %s | %s %s | window %s" % [
		OS.get_processor_name(), OS.get_processor_count(),
		roundi(OS.get_memory_info()["physical"] / 1073741824.0), RenderingServer.get_video_adapter_name(),
		RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_api_version(),
		RenderingServer.get_current_rendering_method(), Engine.get_version_info().string,
		OS.get_name(), OS.get_version(), DisplayServer.window_get_size()]
	if mode == "ceiling":
		await _ceiling(machine)
		return
	var lines := PackedStringArray(["# " + machine,
		"# %s, %d s measured per run after %d warm-up ticks (60 a second), vsync off" % [
			Time.get_date_string_from_system(), int(seconds), WARMUP_SECONDS * 60],
		"setup,units,ticks,tick_frame_ms,tick_frame_p95_ms,draw_ms,step_ms,catchup_frames,catchup_ms,ticks_per_s"])
	print(lines[0])
	print(lines[2])
	for setup in setups:
		for n in sizes:
			var line := _row(await _measure(setup, n))
			print(line)
			lines.append(line)
	_write("%s.csv" % Time.get_date_string_from_system(), lines)
	quit(0)

## The most units each setup holds at each target frame rate, found by
## doubling and then bisecting. Every size tried is a row of the CSV; the
## summary lines at the end (`# ceiling,...`) are what BENCHMARK.md quotes.
func _ceiling(machine: String) -> void:
	var lines := PackedStringArray(["# " + machine,
		"# %s, ceiling search: %d s measured per size after %d s of warm-up, vsync off; holds = p95 one-step frame under 1000/fps ms, catch-up frames at most 1%% of steps, and at least %d%% of fps steps a second" % [
			Time.get_date_string_from_system(), int(seconds), WARMUP_SECONDS, int(HOLD_RATE * 100)],
		"fps,setup,units,ticks,tick_frame_ms,tick_frame_p95_ms,draw_ms,step_ms,catchup_frames,catchup_ms,ticks_per_s,holds"])
	print(lines[0])
	print(lines[2])
	var summary := PackedStringArray()
	for fps in targets:
		_rate = fps
		Engine.physics_ticks_per_second = fps
		var budget := 1000.0 / fps
		for setup in setups:
			var held := 0
			var failed := 0
			var n := start_size
			# Double until a size fails (or the cap is passed)...
			while n <= max_size:
				var r := await _measure(setup, n)
				var ok := _holds(r, budget, fps)
				var line := "%d,%s,%s" % [fps, _row(r), "yes" if ok else "no"]
				print(line)
				lines.append(line)
				if not ok:
					failed = n
					break
				held = n
				n *= 2
			# ...then halve the gap until it is within 5%.
			while failed > 0 and failed - held > maxi(int(held * 0.05), 50):
				n = int(round((held + failed) / 100.0)) * 50
				if n <= held or n >= failed:
					break
				var r := await _measure(setup, n)
				var ok := _holds(r, budget, fps)
				var line := "%d,%s,%s" % [fps, _row(r), "yes" if ok else "no"]
				print(line)
				lines.append(line)
				if ok:
					held = n
				else:
					failed = n
			var s := "# ceiling,%d fps,%s,holds %d,fails at %s" % [fps, setup, held,
				str(failed) if failed > 0 else "none tried up to %d" % max_size]
			print(s)
			summary.append(s)
	lines.append_array(summary)
	# Date and time, so a second search the same day does not overwrite the first.
	_write("ceiling-%s.csv" % Time.get_datetime_string_from_system().replace(":", ""), lines)
	quit(0)

## Holding a frame rate means the bad frames fit too, not only the average:
## the 95th-percentile one-step frame is inside the budget, no more than 1% of
## steps came in catch-up frames (a hitch the player sees), and the simulation
## kept 98% of its steps.
func _holds(r: Dictionary, budget: float, fps: int) -> bool:
	return (r.ticks > 0 and r.p95 <= budget and r.catchup <= r.steps * 0.01
		and r.ticks_per_s >= fps * HOLD_RATE)

func _write(file_name: String, lines: PackedStringArray) -> void:
	var dir := "res://benchmark/results"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open("%s/%s" % [dir, file_name], FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()

func _row(r: Dictionary) -> String:
	return "%s,%d,%d,%.2f,%.2f,%.2f,%.2f,%d,%.2f,%.1f" % [r.setup, r.units, r.ticks, r.tick_ms,
		r.p95, r.draw_ms, r.tick_ms - r.draw_ms, r.catchup, r.catchup_ms, r.ticks_per_s]

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

func _measure(setup: String, n: int) -> Dictionary:
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
	for i in WARMUP_SECONDS * _rate:
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
	# Measured to the last frame counted, not to here: freeing the arena and
	# the two frames after it are not part of the run.
	var elapsed := (last - start) / 1e6
	return {"setup": setup, "units": n, "ticks": with_tick.size(), "tick_ms": tick_mean, "p95": p95,
		"draw_ms": draw_mean, "catchup": catchup.size(), "catchup_ms": _mean(catchup),
		"ticks_per_s": total_ticks / elapsed, "steps": total_ticks}

func _mean(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return NAN
	var total := 0.0
	for v in values:
		total += v
	return total / values.size()
