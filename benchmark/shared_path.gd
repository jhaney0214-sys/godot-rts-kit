extends Node3D
## Units in squads of 20 that share one path. One NavigationServer3D query per
## squad, no NavigationAgent3D nodes, and one script moving every unit. Each
## unit is still its own MeshInstance3D, so drawing costs the same as the
## agent setups and only the movement differs.

const SQUAD := 20

var speed := 5.0
var _units: Array[Node3D] = []
var _offsets: PackedVector3Array = []
var _squads: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _half := 100.0

func setup(count: int, mesh: Mesh, unit_speed: float, seed_value: int, map_half: float) -> void:
	speed = unit_speed
	_rng.seed = seed_value
	_half = map_half
	for i in count:
		var unit := MeshInstance3D.new()
		unit.mesh = mesh
		add_child(unit)
		_units.append(unit)
		# A loose 5-wide block behind the squad's anchor.
		var slot := i % SQUAD
		_offsets.append(Vector3((slot % 5 - 2) * 1.5, 0.0, (slot / 5) * 1.5))
	for s in ceili(float(count) / SQUAD):
		var start := _random_point()
		_squads.append({"anchor": start, "path": PackedVector3Array(), "next": 0})
		for i in range(s * SQUAD, mini((s + 1) * SQUAD, count)):
			_units[i].position = start + _offsets[i]

func _random_point() -> Vector3:
	var p := Vector3(_rng.randf_range(-_half, _half), 0.0, _rng.randf_range(-_half, _half))
	return NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, p)

func _physics_process(delta: float) -> void:
	var step := speed * delta
	for s in _squads.size():
		var squad: Dictionary = _squads[s]
		var path: PackedVector3Array = squad.path
		var next: int = squad.next
		if next >= path.size():
			squad.path = NavigationServer3D.map_get_path(
				get_world_3d().navigation_map, squad.anchor, _random_point(), true)
			squad.next = 0
			continue
		var anchor: Vector3 = squad.anchor
		var to := path[next] - anchor
		to.y = 0.0
		if to.length() <= step:
			squad.anchor = Vector3(path[next].x, 0.0, path[next].z)
			squad.next = next + 1
		else:
			squad.anchor = anchor + to.normalized() * step
		var target: Vector3 = squad.anchor
		for i in range(s * SQUAD, mini((s + 1) * SQUAD, _units.size())):
			var unit := _units[i]
			var want := target + _offsets[i] - unit.position
			want.y = 0.0
			unit.position += want.limit_length(step * 1.2)
