shader_type spatial;
// Ядро чёрной дыры: чёрный шар, по краю — светящийся фиолетовый ободок (горизонт событий).

render_mode unshaded, cull_back;

uniform vec4 rim_color : source_color = vec4(0.62, 0.3, 1.0, 1.0);
uniform float rim_power = 3.0;
uniform float rim_energy = 4.0;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	ALBEDO = rim_color.rgb * rim * rim_energy;
}
