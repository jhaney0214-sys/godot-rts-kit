extends Node3D
## The RTS Kit demo, built in code so every step is readable in one file.
##
## Blue is yours. Red wanders about in the fog. The walls are baked into the
## navigation grid from their colliders, so routes go around them.

const WORLD := Rect2(-100, -100, 200, 200)
const UnitScript := preload("demo_unit.gd")

var nav := RTSNavGrid.new(WORLD, 2.0)
var _rng := RandomNumberGenerator.new()
var _enemies: Array[Node3D] = []

func _ready() -> void:
	_rng.seed = 7
	_build_world()

	var rig := RTSCameraRig.new()
	rig.name = "CameraRig"
	rig.bounds = WORLD
	rig.position = Vector3(-60, 0, 60)
	add_child(rig)

	var fog := RTSFogOfWar.new()
	fog.name = "Fog"
	fog.world_rect = WORLD
	add_child(fog)

	var selection := RTSSelection.new()
	selection.name = "Selection"
	selection.camera_rig = rig
	add_child(selection)

	var hud := CanvasLayer.new()
	add_child(hud)
	var minimap := RTSMinimap.new()
	minimap.world_rect = WORLD
	minimap.position = Vector2(12, 12)
	minimap.size = Vector2(190, 190)
	hud.add_child(minimap)
	var help := Label.new()
	help.text = "Left drag: select   Right click: move   Shift: add / queue   Double-click: all of a kind\nCtrl+1-9: set group   1-9: recall (twice: jump)   H: stop   WASD / edges / middle drag: pan   Wheel: zoom"
	if OS.has_feature("web"):
		# A browser keeps Ctrl+1-9 for its own tabs, so groups cannot be set there.
		help.text = "Left drag: select   Right click: move   Shift: add / queue   Double-click: all of a kind\nH: stop   WASD / edges / middle drag: pan   Wheel: zoom"
	help.position = Vector2(214, 12)
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help.add_theme_color_override("font_outline_color", Color.BLACK)
	help.add_theme_constant_override("outline_size", 4)
	hud.add_child(help)

	# Walls must be in the physics world before the grid can be baked from them.
	await get_tree().physics_frame
	nav.bake_from_physics(get_world_3d(), 2, 1.2)

	for i in 8:
		_spawn(0, "rifle" if i < 6 else "heavy", Vector3(-70 + (i % 4) * 3.0, 0, 70 - (i / 4) * 3.0))
	for i in 10:
		_enemies.append(_spawn(1, "rifle", Vector3(_rng.randf_range(0, 80), 0, _rng.randf_range(-80, 20))))

	var wander := Timer.new()
	wander.wait_time = 4.0
	wander.autostart = true
	wander.timeout.connect(_wander)
	add_child(wander)
	_wander()

func _spawn(team: int, kind: String, at: Vector3) -> Node3D:
	var unit = UnitScript.new()
	unit.team = team
	unit.unit_type = kind
	unit.nav = nav
	unit.color = Color(0.35, 0.7, 1.0) if team == 0 else Color(1.0, 0.35, 0.3)
	if kind == "heavy":
		unit.color = unit.color.darkened(0.35)
		unit.speed = 6.0
		unit.vision_radius = 22.0
	unit.position = at
	add_child(unit)
	return unit

func _wander() -> void:
	for enemy in _enemies:
		if is_instance_valid(enemy) and enemy.call("is_idle") and _rng.randf() < 0.5:
			var goal := enemy.global_position + Vector3(_rng.randf_range(-25, 25), 0, _rng.randf_range(-25, 25))
			goal.x = clampf(goal.x, -95, 95)
			goal.z = clampf(goal.z, -95, 95)
			enemy.call("rts_move", goal, false)

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.05, 0.06, 0.07)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.58, 0.6)
	env.environment = environment
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)

	# Ground on layer 1: the camera's order raycasts hit it; the nav bake does not.
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = WORLD.size
	plane.mesh = mesh
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.3, 0.42, 0.27)
	plane.material_override = grass
	ground.add_child(plane)
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WORLD.size.x, 1.0, WORLD.size.y)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	ground.add_child(floor_shape)
	add_child(ground)

	# Walls on layer 2: what the nav grid is baked from.
	_wall(Vector3(-20, 0, 10), Vector3(4, 5, 90))
	_wall(Vector3(25, 0, -35), Vector3(70, 5, 4))
	_wall(Vector3(40, 0, 45), Vector3(4, 5, 50))
	for i in 12:
		_wall(Vector3(_rng.randf_range(-90, 90), 0, _rng.randf_range(-90, 90)), Vector3(5, 3, 5))

func _wall(centre: Vector3, extent: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.position = centre + Vector3(0, extent.y * 0.5, 0)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = extent
	mesh_instance.mesh = mesh
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.55, 0.52, 0.48)
	mesh_instance.material_override = stone
	body.add_child(mesh_instance)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = extent
	shape.shape = box
	body.add_child(shape)
	add_child(body)
