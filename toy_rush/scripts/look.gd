class_name Look
extends RefCounted
## Global art direction (v0.3, matched to the bright mobile key-art reference):
## high-key sunny lighting, sky/ground bounce ambient (top faces bright, undersides greener),
## soft light shadows falling to the lower-right of the screen, low contrast, saturated pastels.

const SUN_COLOR := Color("fff4dc")
const SKY_TOP := Color("cfeaff")
const SKY_HORIZON := Color("eef8ff")
const GROUND_BOUNCE := Color("8ccf5a")
const OUTLINE_NAVY := Color("1b2150")

static func environment() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("9fdcf7")
	# hemispheric ambient: sky from above, grass bounce from below
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = SKY_TOP
	sm.sky_horizon_color = SKY_HORIZON
	sm.ground_horizon_color = Color("bfe39a")
	sm.ground_bottom_color = GROUND_BOUNCE
	sm.sun_angle_max = 0.0
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 1.0
	e.ambient_light_energy = 0.42
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.tonemap_exposure = 1.0
	e.tonemap_white = 6.0
	e.glow_enabled = true
	e.glow_intensity = 0.35
	e.glow_bloom = 0.0
	e.glow_hdr_threshold = 2.2
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	e.ssao_enabled = true
	e.ssao_radius = 0.9
	e.ssao_intensity = 0.7
	e.ssao_power = 1.0
	e.ssao_light_affect = 0.0
	e.adjustment_enabled = true
	e.adjustment_brightness = 1.0
	e.adjustment_contrast = 1.02
	e.adjustment_saturation = 1.06
	return e

## Sun from the upper-left of the (yaw 45 deg) quarter-view screen, shadows fall lower-right.
static func sun() -> DirectionalLight3D:
	var s := DirectionalLight3D.new()
	s.light_color = SUN_COLOR
	s.light_energy = 0.72
	s.shadow_enabled = true
	s.shadow_opacity = 0.68
	s.shadow_blur = 1.4
	s.directional_shadow_max_distance = 70.0
	var pos := Vector3(-12.0, 15.0, -3.0)
	s.transform = Transform3D(Basis.looking_at(-pos.normalized(), Vector3.UP), pos)
	return s

## "Ruined cat arena" mood for the in-game map: dusky navy surroundings, cool moonlit
## ambient, warm key light, and enough glow for the lime grass and cyan statue eyes to bloom.
static func arena_environment() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("161c2c")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("8292c0")
	e.ambient_light_energy = 0.62
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.tonemap_exposure = 1.0
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_strength = 1.0
	e.glow_bloom = 0.0
	e.glow_hdr_threshold = 1.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	e.ssao_enabled = true
	e.ssao_radius = 0.8
	e.ssao_intensity = 1.4
	e.ssao_power = 1.2
	e.ssao_light_affect = 0.0
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.05
	e.adjustment_saturation = 1.14
	return e

static func arena_sun() -> DirectionalLight3D:
	var s := sun()
	s.light_color = Color("ffe6bd")
	s.light_energy = 0.9
	s.shadow_opacity = 0.75
	return s

## Low-poly faceted version of a mesh (rocks look chiseled like the reference).
static func faceted(mesh: Mesh) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	st.deindex()
	st.generate_normals()
	return st.commit()

static var _rock: ArrayMesh
static func rock_mesh() -> ArrayMesh:
	if _rock == null:
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 7
		s.rings = 4
		_rock = faceted(s)
	return _rock
