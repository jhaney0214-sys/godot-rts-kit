extends Node3D
## Units as plain data, steered by precomputed flow fields and drawn by one
## MultiMeshInstance3D. No node per unit and no path query per unit: each
## unit reads the direction stored in the cell it stands on.

const CELL := 1.0
const GOALS := 4

var speed := 5.0
var _half := 100.0
var _size := 200
var _blocked := PackedByteArray()
var _fields: Array[PackedVector2Array] = []
var _goals: PackedVector3Array = []
var _pos := PackedVector3Array()
var _goal_of := PackedInt32Array()
var _buffer := PackedFloat32Array()
var _multimesh := MultiMesh.new()

func setup(count: int, mesh: Mesh, unit_speed: float, seed_value: int, map_half: float, obstacles: Array) -> void:
	speed = unit_speed
	_half = map_half
	_size = int(map_half * 2.0 / CELL)
	_blocked.resize(_size * _size)
	for cy in _size:
		for cx in _size:
			var c := _centre(cx, cy)
			for r in obstacles:
				if (r as Rect2).grow(0.5).has_point(Vector2(c.x, c.z)):
					_blocked[cy * _size + cx] = 1
	var h := map_half * 0.8
	_goals = PackedVector3Array([Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h)])
	for g in GOALS:
		_fields.append(_field_to(_goals[g]))

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_pos.resize(count)
	_goal_of.resize(count)
	for i in count:
		var p := Vector3.ZERO
		while true:
			p = Vector3(rng.randf_range(-_half, _half), 0.0, rng.randf_range(-_half, _half))
			if not _blocked[_index(p)]:
				break
		_pos[i] = p
		_goal_of[i] = i % GOALS

	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.mesh = mesh
	_multimesh.instance_count = count
	_buffer.resize(count * 12)
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = _multimesh
	add_child(instance)
	_upload()

func _centre(cx: int, cy: int) -> Vector3:
	return Vector3(-_half + (cx + 0.5) * CELL, 0.0, -_half + (cy + 0.5) * CELL)

func _index(p: Vector3) -> int:
	var cx := clampi(int((p.x + _half) / CELL), 0, _size - 1)
	var cy := clampi(int((p.z + _half) / CELL), 0, _size - 1)
	return cy * _size + cx

## Breadth-first distance from the goal over open cells, then each cell points
## at its lowest neighbour. Computed once; every unit heading there shares it.
func _field_to(goal: Vector3) -> PackedVector2Array:
	var n := _size * _size
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(1 << 30)
	var start := _index(goal)
	dist[start] = 0
	var queue := PackedInt32Array([start])
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var cx := i % _size
		var cy := i / _size
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = cx + d.x
			var ny: int = cy + d.y
			if nx < 0 or ny < 0 or nx >= _size or ny >= _size:
				continue
			var j := ny * _size + nx
			if _blocked[j] or dist[j] <= dist[i] + 1:
				continue
			dist[j] = dist[i] + 1
			queue.append(j)
	var field := PackedVector2Array()
	field.resize(n)
	for i in n:
		var cx := i % _size
		var cy := i / _size
		var best := dist[i]
		var dir := Vector2.ZERO
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := cx + dx
				var ny := cy + dy
				if (dx == 0 and dy == 0) or nx < 0 or ny < 0 or nx >= _size or ny >= _size:
					continue
				var j := ny * _size + nx
				if dist[j] < best:
					best = dist[j]
					dir = Vector2(dx, dy)
		field[i] = dir.normalized()
	return field

func _physics_process(delta: float) -> void:
	var step := speed * delta
	for i in _pos.size():
		var p := _pos[i]
		var g := _goal_of[i]
		if p.distance_to(_goals[g]) < 3.0:
			g = (g + 1) % GOALS
			_goal_of[i] = g
		var dir: Vector2 = _fields[g][_index(p)]
		var moved := p + Vector3(dir.x, 0.0, dir.y) * step
		if not _blocked[_index(moved)]:
			_pos[i] = moved
	_upload()

func _upload() -> void:
	# One buffer write per frame instead of one call per unit.
	for i in _pos.size():
		var p := _pos[i]
		var o := i * 12
		_buffer[o] = 1.0
		_buffer[o + 1] = 0.0
		_buffer[o + 2] = 0.0
		_buffer[o + 3] = p.x
		_buffer[o + 4] = 0.0
		_buffer[o + 5] = 1.0
		_buffer[o + 6] = 0.0
		_buffer[o + 7] = p.y
		_buffer[o + 8] = 0.0
		_buffer[o + 9] = 0.0
		_buffer[o + 10] = 1.0
		_buffer[o + 11] = p.z
	_multimesh.buffer = _buffer
