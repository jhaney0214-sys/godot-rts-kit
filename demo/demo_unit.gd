extends CharacterBody3D
## The demo's unit. Your game will have its own; this shows the whole contract
## the kit needs: a group, a team, and a few optional rts_* methods.

@export var team: int = 0
@export var unit_type: String = "rifle"
@export var vision_radius: float = 16.0
@export var speed: float = 9.0
@export var color: Color = Color(0.35, 0.7, 1.0)

var nav: RTSNavGrid
var _path := PackedVector3Array()
var _queue: Array[Vector3] = []
var _ring: MeshInstance3D

func _ready() -> void:
	add_to_group(RTSKit.UNIT_GROUP)
	# Units only bump walls (layer 2), not each other or the ground, so a
	# crowd never jams in a doorway and height stays where it was put.
	collision_layer = 4
	collision_mask = 2
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.6
	capsule.height = 2.0 if unit_type == "rifle" else 2.8
	body.mesh = capsule
	body.position.y = capsule.height * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	body.material_override = mat
	add_child(body)
	var shape := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.6
	capsule_shape.height = capsule.height
	shape.shape = capsule_shape
	shape.position.y = capsule.height * 0.5
	add_child(shape)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.0
	torus.outer_radius = 1.25
	_ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(0.5, 1.0, 0.6)
	_ring.material_override = ring_mat
	_ring.position.y = 0.05
	_ring.visible = false
	add_child(_ring)

func rts_set_selected(on: bool) -> void:
	_ring.visible = on

func rts_move(point: Vector3, queued: bool) -> void:
	point.y = global_position.y
	if queued and not is_idle():
		_queue.append(point)
		return
	_queue.clear()
	_set_goal(point)

func rts_stop() -> void:
	_queue.clear()
	_path = PackedVector3Array()

func is_idle() -> bool:
	return _path.is_empty() and _queue.is_empty()

func _set_goal(point: Vector3) -> void:
	_path = nav.route(global_position, point) if nav != null else PackedVector3Array([point])

func _physics_process(_delta: float) -> void:
	if _path.is_empty():
		if not _queue.is_empty():
			_set_goal(_queue.pop_front())
		velocity = Vector3.ZERO
		return
	var target := _path[0]
	var flat := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if flat.length() < 0.5:
		_path.remove_at(0)
		return
	velocity = flat.normalized() * speed
	move_and_slide()
