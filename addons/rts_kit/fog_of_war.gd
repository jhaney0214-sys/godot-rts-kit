class_name RTSFogOfWar
extends Node3D
## Fog of war: what your side can see now, what it has seen, and what it never has.
##
## Vision comes from every unit of [member team] with a [code]vision_radius[/code].
## Two masks are kept: [i]visible[/i] (seen right now) and [i]explored[/i] (ever
## seen, latched). The shroud is drawn as a full-screen depth-aware pass, so it
## covers terrain, props and units alike. With [member hide_unseen_units] on,
## other teams' units outside current vision are hidden, which also makes them
## unclickable for [RTSSelection].

@export var team: int = 0
## The ground the fog covers, in world XZ.
@export var world_rect: Rect2 = Rect2(-100, -100, 200, 200)
## Mask texels across the longer side. Must be fine against the smallest vision
## radius; 256 over 200 units is under a unit per texel.
@export var resolution: int = 256
## Seconds between rebuilds. Vision moves at walking pace; every frame is waste.
@export var refresh_interval: float = 0.15
@export var hide_unseen_units: bool = true
@export var fog_color: Color = Color(0.02, 0.025, 0.03):
	set(value):
		fog_color = value
		_push_uniforms()
@export_range(0.0, 1.0) var unexplored_alpha: float = 1.0:
	set(value):
		unexplored_alpha = value
		_push_uniforms()
@export_range(0.0, 1.0) var remembered_alpha: float = 0.6:
	set(value):
		remembered_alpha = value
		_push_uniforms()
## Draw the shroud. Off, the masks still update (minimap, hiding, queries).
@export var shroud_visible: bool = true:
	set(value):
		shroud_visible = value
		if _mesh != null:
			_mesh.visible = value

var visible_texture: ImageTexture
var explored_texture: ImageTexture

var _w: int = 1
var _h: int = 1
var _visible_bytes := PackedByteArray()
var _explored_bytes := PackedByteArray()
var _visible_img: Image
var _explored_img: Image
var _material: ShaderMaterial
var _mesh: MeshInstance3D
var _timer: float = 0.0

func _ready() -> void:
	add_to_group(RTSKit.FOG_GROUP)
	var longest: float = maxf(world_rect.size.x, world_rect.size.y)
	_w = maxi(1, roundi(resolution * world_rect.size.x / longest))
	_h = maxi(1, roundi(resolution * world_rect.size.y / longest))
	_visible_bytes.resize(_w * _h)
	_explored_bytes.resize(_w * _h)
	_visible_bytes.fill(0)
	_explored_bytes.fill(0)
	_visible_img = Image.create_from_data(_w, _h, false, Image.FORMAT_L8, _visible_bytes)
	_explored_img = Image.create_from_data(_w, _h, false, Image.FORMAT_L8, _explored_bytes)
	visible_texture = ImageTexture.create_from_image(_visible_img)
	explored_texture = ImageTexture.create_from_image(_explored_img)

	_material = ShaderMaterial.new()
	_material.shader = preload("fog.gdshader")
	_material.render_priority = 100
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_mesh = MeshInstance3D.new()
	_mesh.name = "Shroud"
	_mesh.mesh = quad
	_mesh.material_override = _material
	# The quad is pinned to the screen in the shader, so its real position means
	# nothing; a huge cull margin stops Godot ever culling it.
	_mesh.extra_cull_margin = 16384.0
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.visible = shroud_visible
	add_child(_mesh)
	_push_uniforms()
	refresh()

func _push_uniforms() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("visible_tex", visible_texture)
	_material.set_shader_parameter("explored_tex", explored_texture)
	_material.set_shader_parameter("world_origin", world_rect.position)
	_material.set_shader_parameter("world_size", world_rect.size)
	_material.set_shader_parameter("fog_color", Vector3(fog_color.r, fog_color.g, fog_color.b))
	_material.set_shader_parameter("unexplored_alpha", unexplored_alpha)
	_material.set_shader_parameter("remembered_alpha", remembered_alpha)

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= refresh_interval:
		_timer = 0.0
		refresh()

## Rebuild the masks now. Called on a timer; call it yourself after teleports.
func refresh() -> void:
	# One memset in C++; clearing this in a GDScript loop would cost more than
	# the rest of the system put together.
	_visible_bytes.fill(0)
	var tree := get_tree()
	if tree != null:
		for unit in RTSKit.units(tree, team):
			var sight := RTSKit.vision_of(unit)
			if sight > 0.0:
				_stamp(unit.global_position, sight)
		if hide_unseen_units:
			for unit in RTSKit.units(tree):
				if RTSKit.team_of(unit) != team:
					unit.visible = visible_at(unit.global_position)
	_visible_img.set_data(_w, _h, false, Image.FORMAT_L8, _visible_bytes)
	_explored_img.set_data(_w, _h, false, Image.FORMAT_L8, _explored_bytes)
	visible_texture.update(_visible_img)
	explored_texture.update(_explored_img)

## Open a circle of both masks around a world point. Public so a flare, a spell
## or a scan can reveal ground without a unit.
func reveal(at: Vector3, radius: float) -> void:
	_stamp(at, radius)

## Mark all ground as explored (a "map revealed" cheat, a replay, an editor).
func explore_all() -> void:
	_explored_bytes.fill(255)

func reset() -> void:
	_explored_bytes.fill(0)
	_visible_bytes.fill(0)

func _stamp(at: Vector3, radius: float) -> void:
	var per_x: float = float(_w) / world_rect.size.x
	var per_y: float = float(_h) / world_rect.size.y
	var cx: float = (at.x - world_rect.position.x) * per_x
	var cy: float = (at.z - world_rect.position.y) * per_y
	var r: float = radius * per_x
	var lo_x: int = maxi(0, floori(cx - r))
	var hi_x: int = mini(_w - 1, ceili(cx + r))
	var lo_y: int = maxi(0, floori(cy - r))
	var hi_y: int = mini(_h - 1, ceili(cy + r))
	if lo_x > hi_x or lo_y > hi_y:
		return
	var r2: float = r * r
	for y in range(lo_y, hi_y + 1):
		var dy: float = float(y) + 0.5 - cy
		var row: int = y * _w
		for x in range(lo_x, hi_x + 1):
			var dx: float = float(x) + 0.5 - cx
			var d2: float = dx * dx + dy * dy
			if d2 > r2:
				continue
			# Feathered over the outer quarter of the radius, so linear filtering
			# gives a soft rim instead of a staircase circle.
			var v: int = int(clampf((1.0 - sqrt(d2) / maxf(r, 0.001)) * 4.0, 0.0, 1.0) * 255.0)
			var i: int = row + x
			if v > _visible_bytes[i]:
				_visible_bytes[i] = v
			# Explored keeps the brightest it has ever been, so the edge of
			# remembered ground is feathered like the edge of vision.
			if v > _explored_bytes[i]:
				_explored_bytes[i] = v

func _index(at: Vector3) -> int:
	var ix: int = floori((at.x - world_rect.position.x) / world_rect.size.x * _w)
	var iy: int = floori((at.z - world_rect.position.y) / world_rect.size.y * _h)
	if ix < 0 or iy < 0 or ix >= _w or iy >= _h:
		return -1
	return iy * _w + ix

## Can [member team] see this point right now?
func visible_at(at: Vector3) -> bool:
	var i := _index(at)
	return i >= 0 and _visible_bytes[i] > 0

## Has [member team] ever seen this point?
func explored_at(at: Vector3) -> bool:
	var i := _index(at)
	return i >= 0 and _explored_bytes[i] > 32
