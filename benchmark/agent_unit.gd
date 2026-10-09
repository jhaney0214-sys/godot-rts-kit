extends Node3D
## One unit steered by its own NavigationAgent3D, with or without avoidance.
## This is the setup the Godot docs teach, and the one most projects start from.

var agent: NavigationAgent3D
var speed := 5.0
var _rng := RandomNumberGenerator.new()
var _half := 100.0
var _started := false

func setup(mesh: Mesh, avoid: bool, unit_speed: float, seed_value: int, map_half: float) -> void:
	var body := MeshInstance3D.new()
	body.mesh = mesh
	add_child(body)
	speed = unit_speed
	_rng.seed = seed_value
	_half = map_half
	agent = NavigationAgent3D.new()
	agent.radius = 0.5
	agent.max_speed = speed
	agent.path_desired_distance = 1.0
	agent.target_desired_distance = 1.5
	agent.avoidance_enabled = avoid
	if avoid:
		agent.velocity_computed.connect(_on_velocity_computed)
	add_child(agent)

func _physics_process(delta: float) -> void:
	if not _started or agent.is_navigation_finished():
		_started = true
		agent.target_position = Vector3(_rng.randf_range(-_half, _half), 0.0, _rng.randf_range(-_half, _half))
		return
	var to := agent.get_next_path_position() - global_position
	to.y = 0.0
	var velocity := to.normalized() * speed if to.length() > 0.01 else Vector3.ZERO
	if agent.avoidance_enabled:
		agent.velocity = velocity
	else:
		global_position += velocity * delta

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	global_position += safe_velocity * get_physics_process_delta_time()
