shader_type spatial;
// Аккреционный диск чёрной дыры: плоское кольцо, по нему бегут закрученные внутрь полосы;
// у внутреннего края ярче и светлее, к внешнему гаснет. Аддитивный, без освещения.

render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 inner_color : source_color = vec4(0.95, 0.8, 1.0, 1.0);
uniform vec4 outer_color : source_color = vec4(0.45, 0.12, 0.95, 1.0);
uniform float inner = 0.9;
uniform float outer = 3.2;
uniform float spin = 6.0;
uniform float energy = 2.2;

varying vec2 flat_pos;

void vertex() {
	flat_pos = VERTEX.xz;
}

void fragment() {
	float r = length(flat_pos);
	float k = clamp((r - inner) / (outer - inner), 0.0, 1.0);
	float a = atan(flat_pos.y, flat_pos.x);
	float swirl = 0.55 + 0.45 * sin(a * 3.0 + r * 3.5 - TIME * spin);
	float fade = smoothstep(0.0, 0.08, k) * pow(1.0 - k, 1.6);
	ALBEDO = mix(inner_color.rgb, outer_color.rgb, k) * swirl * fade * energy;
}
