extends Node3D

# ============================================================
# World Generator v5 — Part 1/2
# - LOD via visibility_range (dithering fade)
# - 0-10m visible, 10-35m fade, 35m+ culled
# - Physics frozen beyond 40m
# ============================================================

const SEED := 123465
const GROUND_SIZE := 750
const BOUNDARY_MARGIN := 6.0
const HOUSES := 10
const BOXES_PER_HOUSE := 3
const JUNK_COUNT := 40
const BARREL_COUNT := 12
const WALLS := 8
const TOWERS := 3
const FLOOR_TEXTURE_PATH := "res://assets/Sprites/floor_texture.png"

const FADE_START := 10.0
const FADE_END := 35.0
const FREEZE_AT := 40.0

var _buildings: Array = []
var _current_building: Dictionary = {}

var _box_data: Array = []
var _junk_data: Array = []
var _barrel_data: Array = []
var _collision_data: Array = []

var _sync_boxes: Array = []
var _sync_junk: Array = []
var _sync_barrels: Array = []

var _mm_boxes: MultiMesh
var _mm_junk: MultiMesh
var _mm_barrels: MultiMesh

var _structures_root: Node3D
var _collision_root: StaticBody3D
var _boxes_root: Node3D
var _junk_root: Node3D
var _barrels_root: Node3D
var _boxes_bodies: Node3D
var _junk_bodies: Node3D
var _barrels_bodies: Node3D

var _player: Node3D = null

func _ready() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = SEED
    _setup_roots()
    _build_ground()
    _build_boundary()
    var half := GROUND_SIZE / 2.0 - 20.0
    var house_positions: Array = []
    for i in HOUSES:
        var ang := TAU * float(i) / HOUSES + rng.randf_range(-0.15, 0.15)
        var dist := rng.randf_range(30.0, half)
        var pos := Vector3(cos(ang) * dist, 0, sin(ang) * dist)
        var rot := rng.randf_range(0.0, TAU)
        house_positions.append({"pos": pos, "rot": rot})
        _plan_house(pos, rot, rng)
    for i in WALLS:
        var ang := TAU * (float(i) / WALLS + 0.06)
        var dist := rng.randf_range(40.0, half)
        _plan_wall(Vector3(cos(ang) * dist, 0, sin(ang) * dist), rng)
    for i in TOWERS:
        var ang := TAU * (float(i) / TOWERS + 0.2)
        var dist := rng.randf_range(45.0, half)
        _plan_tower(Vector3(cos(ang) * dist, 0, sin(ang) * dist), rng)
    _flush_buildings()
    for h in house_positions:
        for i in BOXES_PER_HOUSE:
            var off := Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))
            _plan_box(h["pos"] + off, rng)
    _flush_boxes()
    for i in JUNK_COUNT:
        var pos := Vector3(rng.randf_range(-half, half), 0, rng.randf_range(-half, half))
        _plan_junk(pos, rng)
    _flush_junk()
    for i in BARREL_COUNT:
        var pos := Vector3(rng.randf_range(-half, half), 0, rng.randf_range(-half, half))
        _plan_barrel(pos, rng)
    _flush_barrels()
    call_deferred("_find_player")
    var t := Timer.new()
    t.wait_time = 0.5
    t.autostart = true
    t.timeout.connect(_find_player)
    add_child(t)

func _find_player() -> void:
    var p := get_tree().get_first_node_in_group("player")
    if p != null and p is Node3D:
        _player = p

func _physics_process(_delta: float) -> void:
    if _player == null or not is_instance_valid(_player):
        return
    var ppos := _player.global_position
    for e in _sync_boxes:
        var body = e["body"]
        if not is_instance_valid(body):
            continue
        var d := ppos.distance_to(body.global_position)
        if d > FREEZE_AT:
            if not body.freeze:
                body.freeze = true
        else:
            if body.freeze:
                body.freeze = false
            if _mm_boxes != null:
                _mm_boxes.set_instance_transform(e["i"], body.global_transform)
    for e in _sync_junk:
        var body = e["body"]
        if not is_instance_valid(body):
            continue
        var d := ppos.distance_to(body.global_position)
        if d > FREEZE_AT:
            if not body.freeze:
                body.freeze = true
        else:
            if body.freeze:
                body.freeze = false
            if _mm_junk != null:
                var x: Transform3D = body.global_transform
                x.basis = x.basis.scaled(e["size"])
                _mm_junk.set_instance_transform(e["i"], x)
    for e in _sync_barrels:
        var body = e["body"]
        if not is_instance_valid(body):
            continue
        var d := ppos.distance_to(body.global_position)
        if d > FREEZE_AT:
            if not body.freeze:
                body.freeze = true
        else:
            if body.freeze:
                body.freeze = false
            if _mm_barrels != null:
                _mm_barrels.set_instance_transform(e["i"], body.global_transform)

func _setup_roots() -> void:
    _structures_root = Node3D.new()
    _structures_root.name = "Structures"
    add_child(_structures_root)
    _collision_root = StaticBody3D.new()
    _collision_root.name = "WorldCollision"
    add_child(_collision_root)
    _boxes_root = Node3D.new()
    _boxes_root.name = "Boxes"
    add_child(_boxes_root)
    _boxes_bodies = Node3D.new()
    _boxes_bodies.name = "Bodies"
    _boxes_root.add_child(_boxes_bodies)
    _junk_root = Node3D.new()
    _junk_root.name = "Junk"
    add_child(_junk_root)
    _junk_bodies = Node3D.new()
    _junk_bodies.name = "Bodies"
    _junk_root.add_child(_junk_bodies)
    _barrels_root = Node3D.new()
    _barrels_root.name = "Barrels"
    add_child(_barrels_root)
    _barrels_bodies = Node3D.new()
    _barrels_bodies.name = "Bodies"
    _barrels_root.add_child(_barrels_bodies)

func _build_ground() -> void:
    var ground := StaticBody3D.new()
    ground.name = "Ground"
    add_child(ground)
    var mesh := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
    var tex: Texture2D = load(FLOOR_TEXTURE_PATH)
    var mat := StandardMaterial3D.new()
    if tex == null:
        mat.albedo_color = Color(0.42, 0.55, 0.32)
    else:
        mat.albedo_texture = tex
        mat.uv1_scale = Vector3(GROUND_SIZE / 4.0, GROUND_SIZE / 4.0, 1.0)
        mat.roughness = 0.9
    plane.material = mat
    mesh.mesh = plane
    ground.add_child(mesh)
    var col := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(GROUND_SIZE, 1, GROUND_SIZE)
    col.shape = shape
    col.position = Vector3(0, -0.5, 0)
    ground.add_child(col)

func _build_boundary() -> void:
    var boundary := StaticBody3D.new()
    boundary.name = "Boundary"
    add_child(boundary)
    var lim := GROUND_SIZE / 2.0 - BOUNDARY_MARGIN
    var wall_h := 30.0
    var z_size := Vector3(GROUND_SIZE, wall_h, 2.0)
    var x_size := Vector3(2.0, wall_h, GROUND_SIZE)
    var configs := [
        {"pos": Vector3(0, 10, -lim), "size": z_size},
        {"pos": Vector3(0, 10, lim), "size": z_size},
        {"pos": Vector3(-lim, 10, 0), "size": x_size},
        {"pos": Vector3(lim, 10, 0), "size": x_size}
    ]
    for cfg in configs:
        var col := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = cfg["size"]
        col.shape = shape
        col.position = cfg["pos"]
        boundary.add_child(col)

func _apply_lod(mmi: MultiMeshInstance3D) -> void:
    mmi.visibility_range_begin = 0.0
    mmi.visibility_range_begin_margin = 0.0
    mmi.visibility_range_end = FADE_END
    mmi.visibility_range_end_margin = FADE_END - FADE_START
    mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

func _begin_building() -> void:
    _current_building = {"solid": [], "windows": [], "doors": []}

func _end_building() -> void:
    if _current_building.has("solid") and _current_building["solid"].size() > 0:
        _buildings.append(_current_building.duplicate(true))
    elif _current_building.has("windows") and _current_building["windows"].size() > 0:
        _buildings.append(_current_building.duplicate(true))
    _current_building = {}

func _plan_wall_piece(base: Transform3D, pos: Vector3, size: Vector3, color: Color) -> void:
    var t := base * Transform3D(Basis().scaled(size), pos)
    if not _current_building.has("solid"):
        _current_building["solid"] = []
    _current_building["solid"].append({"t": t, "c": color})
    var shape := BoxShape3D.new()
    shape.size = size
    var col_xform := base * Transform3D(Basis(), pos)
    _collision_data.append({"shape": shape, "xform": col_xform})

func _plan_window_local(base: Transform3D, pos: Vector3, size: Vector3) -> void:
    var t := base * Transform3D(Basis().scaled(size), pos)
    if not _current_building.has("windows"):
        _current_building["windows"] = []
    _current_building["windows"].append(t)

func _plan_house(pos: Vector3, rot_y: float, rng: RandomNumberGenerator) -> void:
    _begin_building()
    var base := Transform3D(Basis(Vector3.UP, rot_y), Vector3(pos.x, 0, pos.z))
    var w := rng.randf_range(5.0, 8.0)
    var d := rng.randf_range(5.0, 8.0)
    var h := rng.randf_range(2.8, 3.8)
    var palettes := [
        Color(0.9, 0.45, 0.4), Color(0.95, 0.75, 0.35), Color(0.45, 0.7, 0.9),
        Color(0.6, 0.85, 0.55), Color(0.85, 0.6, 0.85), Color(0.95, 0.6, 0.5),
        Color(0.65, 0.8, 0.8), Color(0.9, 0.8, 0.55)
    ]
    var body_col: Color = palettes[rng.randi() % palettes.size()]
    var trim_col := body_col.darkened(0.35)
    var roof_cols := [Color(0.45, 0.2, 0.15), Color(0.3, 0.3, 0.35), Color(0.55, 0.3, 0.2), Color(0.25, 0.4, 0.3)]
    var roof_col: Color = roof_cols[rng.randi() % roof_cols.size()]
    _plan_wall_piece(base, Vector3(0, h / 2, -d / 2), Vector3(w, h, 0.3), body_col)
    _plan_wall_piece(base, Vector3(-w / 2, h / 2, 0), Vector3(0.3, h, d), body_col)
    _plan_wall_piece(base, Vector3(w / 2, h / 2, 0), Vector3(0.3, h, d), body_col)
    _plan_wall_piece(base, Vector3(-w / 4, h / 2, d / 2), Vector3(w / 2, h, 0.3), body_col)
    _plan_wall_piece(base, Vector3(w / 4, h / 2, d / 2), Vector3(w / 2, h, 0.3), body_col)
    _plan_wall_piece(base, Vector3(0, h - 0.25, d / 2), Vector3(w / 2, 0.5, 0.3), body_col)
    _plan_wall_piece(base, Vector3(0, h + 0.15, 0), Vector3(w + 0.8, 0.3, d + 0.8), roof_col)
    _plan_wall_piece(base, Vector3(0, h + 0.45, 0), Vector3(w + 1.0, 0.25, d + 1.0), trim_col)
    _plan_window_local(base, Vector3(-w / 5, h * 0.6, -d / 2 - 0.18), Vector3(0.9, 1.0, 0.1))
    _plan_window_local(base, Vector3(w / 5, h * 0.6, -d / 2 - 0.18), Vector3(0.9, 1.0, 0.1))
    _plan_window_local(base, Vector3(-w / 2 - 0.18, h * 0.6, -d / 6), Vector3(0.1, 1.0, 0.9))
    _plan_window_local(base, Vector3(w / 2 + 0.18, h * 0.6, d / 6), Vector3(0.1, 1.0, 0.9))
    if not _current_building.has("doors"):
        _current_building["doors"] = []
    _current_building["doors"].append(base * Transform3D(Basis(), Vector3(0, 1.1, d / 2 + 0.18)))
    _end_building()

func _plan_wall(pos: Vector3, rng: RandomNumberGenerator) -> void:
    _begin_building()
    var rot := rng.randf_range(0.0, TAU)
    var base := Transform3D(Basis(Vector3.UP, rot), Vector3(pos.x, 0, pos.z))
    var length := rng.randf_range(6.0, 14.0)
    var hue := rng.randf()
    var c1 := Color.from_hsv(hue, 0.5, 0.75)
    var c2 := c1.darkened(0.25)
    var bricks := int(length / 1.05)
    for i in bricks:
        var offset := Vector3(-length / 2 + 0.55 + i * 1.05, 0.55, 0)
        _plan_wall_piece(base, offset, Vector3(1.0, 1.1, 0.4), c1)
        if i % 2 == 0:
            _plan_wall_piece(base, offset + Vector3(0, 1.1, 0), Vector3(1.0, 0.4, 0.4), c2)
    _end_building()

func _plan_tower(pos: Vector3, rng: RandomNumberGenerator) -> void:
    _begin_building()
    var rot := rng.randf_range(0.0, TAU)
    var base := Transform3D(Basis(Vector3.UP, rot), Vector3(pos.x, 0, pos.z))
    var wood := Color(0.45, 0.3, 0.15)
    var wood2 := Color(0.5, 0.35, 0.18)
    for x in [-1.0, 1.0]:
        for z in [-1.0, 1.0]:
            _plan_wall_piece(base, Vector3(x, 2.5, z), Vector3(0.3, 5.0, 0.3), wood)
    _plan_wall_piece(base, Vector3(0, 5.2, 0), Vector3(3.2, 0.25, 3.2), wood2)
    _plan_wall_piece(base, Vector3(0, 5.8, -1.5), Vector3(3.2, 0.8, 0.15), wood)
    _plan_wall_piece(base, Vector3(0, 5.8, 1.5), Vector3(3.2, 0.8, 0.15), wood)
    _plan_wall_piece(base, Vector3(-1.5, 5.8, 0), Vector3(0.15, 0.8, 3.2), wood)
    _plan_wall_piece(base, Vector3(1.5, 5.8, 0), Vector3(0.15, 0.8, 3.2), wood)
    for i in 6:
        _plan_wall_piece(base, Vector3(-2.2, 0.4 + i * 0.9, 1.5), Vector3(1.2, 0.15, 0.4), wood2)
    _end_building()



# ============================================================
# FLUSH BUILDINGS (one MMI per building for LOD)
# ============================================================
func _flush_buildings() -> void:
    for i in _buildings.size():
        var b = _buildings[i]
        _create_solid_mmi(b["solid"], i)
        _create_windows_mmi(b.get("windows", []), i)
        _create_doors_mmi(b.get("doors", []), i)
    _flush_combined_collision()

func _create_solid_mmi(data: Array, idx: int) -> void:
    if data.size() == 0:
        return
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.use_colors = true
    var box := BoxMesh.new()
    box.size = Vector3.ONE
    mm.mesh = box
    mm.instance_count = data.size()
    for i in data.size():
        mm.set_instance_transform(i, data[i]["t"])
        mm.set_instance_color(i, data[i]["c"])
    var mmi := MultiMeshInstance3D.new()
    mmi.name = "Solid_" + str(idx)
    mmi.multimesh = mm
    var mat := StandardMaterial3D.new()
    mat.vertex_color_use_as_albedo = true
    mat.roughness = 0.85
    mmi.material_override = mat
    _apply_lod(mmi)
    _structures_root.add_child(mmi)

func _create_windows_mmi(data: Array, idx: int) -> void:
    if data.size() == 0:
        return
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.use_colors = false
    var box := BoxMesh.new()
    box.size = Vector3.ONE
    mm.mesh = box
    mm.instance_count = data.size()
    for i in data.size():
        mm.set_instance_transform(i, data[i])
    var mmi := MultiMeshInstance3D.new()
    mmi.name = "Windows_" + str(idx)
    mmi.multimesh = mm
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(1.0, 0.95, 0.7)
    mat.emission_enabled = true
    mat.emission = Color(1.0, 0.9, 0.5)
    mat.emission_energy_multiplier = 1.5
    mmi.material_override = mat
    _apply_lod(mmi)
    _structures_root.add_child(mmi)

func _create_doors_mmi(data: Array, idx: int) -> void:
    if data.size() == 0:
        return
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.use_colors = false
    var box := BoxMesh.new()
    box.size = Vector3(1.2, 2.2, 0.1)
    mm.mesh = box
    mm.instance_count = data.size()
    for i in data.size():
        mm.set_instance_transform(i, data[i])
    var mmi := MultiMeshInstance3D.new()
    mmi.name = "Doors_" + str(idx)
    mmi.multimesh = mm
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.4, 0.25, 0.12)
    mat.roughness = 0.8
    mmi.material_override = mat
    _apply_lod(mmi)
    _structures_root.add_child(mmi)

func _flush_combined_collision() -> void:
    for e in _collision_data:
        var col := CollisionShape3D.new()
        col.shape = e["shape"]
        col.transform = e["xform"]
        _collision_root.add_child(col)

# ============================================================
# BOXES (combined MMI + physics sync + freeze)
# ============================================================
func _plan_box(pos: Vector3, rng: RandomNumberGenerator) -> void:
    var body := RigidBody3D.new()
    body.mass = 1.0
    var size := Vector3(1, 1, 1)
    body.position = Vector3(pos.x, 0.6 + rng.randf_range(0, 1.5), pos.z)
    body.rotation = Vector3(0, rng.randf_range(0, TAU), 0)
    var col := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    col.shape = shape
    body.add_child(col)
    _boxes_bodies.add_child(body)
    var color := Color.from_hsv(rng.randf_range(0.05, 0.12), 0.6, 0.8)
    var idx := _box_data.size()
    _box_data.append({"t": body.global_transform, "c": color})
    _sync_boxes.append({"body": body, "i": idx})

func _flush_boxes() -> void:
    if _box_data.size() == 0:
        return
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.use_colors = true
    var box := BoxMesh.new()
    box.size = Vector3.ONE
    mm.mesh = box
    mm.instance_count = _box_data.size()
    _mm_boxes = mm
    for i in _box_data.size():
        mm.set_instance_transform(i, _box_data[i]["t"])
        mm.set_instance_color(i, _box_data[i]["c"])
    var mmi := MultiMeshInstance3D.new()
    mmi.name = "MMI_Boxes"
    mmi.multimesh = mm
    var mat := StandardMaterial3D.new()
    mat.vertex_color_use_as_albedo = true
    mat.roughness = 0.7
    mmi.material_override = mat
    _boxes_root.add_child(mmi)

# ============================================================
# JUNK (MultiMesh + physics sync + freeze)
# ============================================================
func _plan_junk(pos: Vector3, rng: RandomNumberGenerator) -> void:
    var body := RigidBody3D.new()
    var size := Vector3(rng.randf_range(0.5, 1.4), rng.randf_range(0.5, 1.4), rng.randf_range(0.5, 1.4))
    body.position = Vector3(pos.x, 3.0 + rng.randf_range(0, 2), pos.z)
    body.rotation = Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0, TAU), rng.randf_range(-0.2, 0.2))
    var col := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    col.shape = shape
    body.add_child(col)
    _junk_bodies.add_child(body)
    var color := Color.from_hsv(rng.randf(), 0.65, 0.9)
    var xform := body.global_transform
    xform.basis = xform.basis.scaled(size)
    var idx := _junk_data.size()
    _junk_data.append({"t": xform, "c": color})
    _sync_junk.append({"body": body, "i": idx, "size": size})

func _flush_junk() -> void:
    if _junk_data.size() == 0:
        return
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.use_colors = true
    var box := BoxMesh.new()
    box.size = Vector3.ONE
    mm.mesh = box
    mm.instance_count = _junk_data.size()
    _mm_junk = mm
    for i in _junk_data.size():
        mm.set_instance_transform(i, _junk_data[i]["t"])
        mm.set_instance_color(i, _junk_data[i]["c"])
    var mmi := MultiMeshInstance3D.new()
    mmi.name = "MMI_Junk"
    mmi.multimesh = mm
    var mat := StandardMaterial3D.new()
    mat.vertex_color_use_as_albedo = true
    mat.roughness = 0.7
    mmi.material_override = mat
    _junk_root.add_child(mmi)

# ============================================================
# BARRELS (MultiMesh + physics sync + freeze)
# ============================================================
func _plan_barrel(pos: Vector3, rng: RandomNumberGenerator) -> void:
    var body := RigidBody3D.new()
    body.mass = 1.0
    body.position = Vector3(pos.x, 0.6, pos.z)
    var col := CollisionShape3D.new()
    var shape := CylinderShape3D.new()
    shape.radius = 0.45
    shape.height = 1.2
    col.shape = shape
    body.add_child(col)
    _barrels_bodies.add_child(body)
    var color := Color.from_hsv(rng.randf(), 0.7, 0.85)
    var idx := _barrel_data.size()
    _barrel_data.append({"t": body.global_transform, "c": color})
    _sync_barrels.append({"body": body, "i": idx})

func _flush_barrels() -> void:
    if _barrel_data.size() == 0:
        return
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.use_colors = true
    var cyl := CylinderMesh.new()
    cyl.top_radius = 0.45
    cyl.bottom_radius = 0.45
    cyl.height = 1.2
    mm.mesh = cyl
    mm.instance_count = _barrel_data.size()
    _mm_barrels = mm
    for i in _barrel_data.size():
        mm.set_instance_transform(i, _barrel_data[i]["t"])
        mm.set_instance_color(i, _barrel_data[i]["c"])
    var mmi := MultiMeshInstance3D.new()
    mmi.name = "MMI_Barrels"
    mmi.multimesh = mm
    var mat := StandardMaterial3D.new()
    mat.vertex_color_use_as_albedo = true
    mat.roughness = 0.6
    mmi.material_override = mat
    _barrels_root.add_child(mmi)