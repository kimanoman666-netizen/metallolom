extends Node
## Материалы для моделей из Blender: заменяют материалы по имени на игровые
## (с шумовой текстурой потёртостей). Отдельный набор — для оружия в руках (шейдер вьюмодели).

const VM_SHADER := """
shader_type spatial;
render_mode skip_vertex_transform, cull_back;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float metallic = 0.5;
uniform float roughness = 0.5;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float grime = 0.0;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
varying vec3 obj_pos;
varying vec3 obj_nrm;
void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz * 0.1;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 w = abs(obj_nrm);
	w = w / (w.x + w.y + w.z + 0.0001);
	vec3 p = obj_pos * 3.0;
	float n = texture(noise_tex, p.yz).r * w.x + texture(noise_tex, p.xz).r * w.y + texture(noise_tex, p.xy).r * w.z;
	float g = smoothstep(0.35, 0.75, n) * grime;
	ALBEDO = albedo.rgb * (1.0 - g * 0.55);
	METALLIC = metallic * (1.0 - g * 0.5);
	ROUGHNESS = clamp(roughness + g * 0.35, 0.0, 1.0);
	EMISSION = emission.rgb * emission_energy;
}
"""

# имя -> [цвет, металличность, шероховатость, грязь, свечение, яркость]
const DEFS := {
	"metal_dark": [Color(0.075, 0.078, 0.085), 0.75, 0.42, 0.6, null, 0.0],
	"metal_mid": [Color(0.17, 0.175, 0.19), 0.8, 0.38, 0.6, null, 0.0],
	"metal_light": [Color(0.45, 0.46, 0.48), 0.9, 0.3, 0.4, null, 0.0],
	"rubber": [Color(0.03, 0.03, 0.032), 0.0, 0.85, 0.2, null, 0.0],
	"joint": [Color(0.62, 0.43, 0.17), 0.85, 0.35, 0.5, Color(1.0, 0.55, 0.15), 0.35],
	"glow_blue": [Color(0.1, 0.5, 1.0), 0.0, 0.3, 0.0, Color(0.15, 0.6, 1.0), 7.0],
	"glow_red": [Color(1.0, 0.1, 0.05), 0.0, 0.3, 0.0, Color(1.0, 0.15, 0.05), 7.0],
	"glass": [Color(0.015, 0.018, 0.03), 0.3, 0.06, 0.0, null, 0.0],
	"steel_worn": [Color(0.5, 0.5, 0.48), 0.85, 0.4, 0.9, null, 0.0],
	"steel_dark": [Color(0.12, 0.12, 0.12), 0.8, 0.45, 0.6, null, 0.0],
	"rust": [Color(0.34, 0.17, 0.08), 0.35, 0.75, 0.8, null, 0.0],
	"paint_white": [Color(0.66, 0.66, 0.63), 0.25, 0.5, 0.9, null, 0.0],
	"brass": [Color(0.62, 0.45, 0.2), 0.9, 0.35, 0.5, null, 0.0],
	"wood": [Color(0.28, 0.15, 0.07), 0.0, 0.65, 0.5, null, 0.0],
	"cable": [Color(0.55, 0.42, 0.25), 0.1, 0.6, 0.3, null, 0.0],
}

var noise: NoiseTexture2D
var nrm: NoiseTexture2D
var _robot := {}
var _vm := {}
var _shader: Shader


func _ready() -> void:
	var n := FastNoiseLite.new()
	n.frequency = 0.05
	n.fractal_octaves = 4
	noise = NoiseTexture2D.new()
	noise.width = 256
	noise.height = 256
	noise.seamless = true
	noise.noise = n
	noise.generate_mipmaps = true
	var n2 := FastNoiseLite.new()
	n2.frequency = 0.09
	n2.seed = 7
	nrm = NoiseTexture2D.new()
	nrm.width = 256
	nrm.height = 256
	nrm.seamless = true
	nrm.as_normal_map = true
	nrm.bump_strength = 3.0
	nrm.noise = n2


func _def(name: String) -> Array:
	return DEFS.get(name, DEFS["metal_dark"])


## Материал для робота/мира (стандартный PBR, потёртости в координатах объекта).
func robot(name: String) -> StandardMaterial3D:
	if _robot.has(name):
		return _robot[name]
	var d := _def(name)
	var m := StandardMaterial3D.new()
	m.albedo_color = d[0]
	m.metallic = d[1]
	m.roughness = d[2]
	if d[3] > 0.0:
		m.roughness_texture = noise
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.normal_enabled = true
		m.normal_texture = nrm
		m.normal_scale = 0.25
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(1.4, 1.4, 1.4)
	m.emission_enabled = true
	if d[4] != null:
		m.emission = d[4]
		m.emission_energy_multiplier = d[5]
	else:
		m.emission = Color(1.0, 0.85, 0.7)
		m.emission_energy_multiplier = 0.0
	_robot[name] = m
	return m


## Материал для оружия в руках.
func vm(name: String) -> ShaderMaterial:
	if _vm.has(name):
		return _vm[name]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = VM_SHADER
	var d := _def(name)
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("albedo", d[0])
	m.set_shader_parameter("metallic", d[1])
	m.set_shader_parameter("roughness", d[2])
	m.set_shader_parameter("grime", d[3])
	m.set_shader_parameter("noise_tex", noise)
	if d[4] != null:
		m.set_shader_parameter("emission", d[4])
		m.set_shader_parameter("emission_energy", d[5])
	_vm[name] = m
	return m


## Ставит материалы моделей по именам из Blender.
func apply(root: Node, viewmodel: bool) -> void:
	var stack: Array = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D and n.mesh:
			n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if viewmodel else n.cast_shadow
			if viewmodel:
				n.extra_cull_margin = 16384.0
			for s in n.mesh.get_surface_count():
				var src: Material = n.mesh.surface_get_material(s)
				var nm := src.resource_name if src else "steel_dark"
				n.set_surface_override_material(s, vm(nm) if viewmodel else robot(nm))
