shader_type spatial;
// Полосы, затягиваемые в воронку по спирали. Вся анимация — в шейдере: у каждой полосы в UV
// начальный угол и сдвиг фазы, в UV2 — угол вершины полосы (вдоль, поперёк). Полоса идёт от
// внешнего радиуса к центру, поворачиваясь на turns оборота, ярче к концу; плоскость — XZ,
// ось воронки — Y (узел можно повернуть, например вдоль ствола).

render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform float radius = 9.0;
uniform float core = 0.8;
uniform float rate = 0.7;
uniform float turns = 1.2;
uniform float height = 1.5;
uniform float width = 0.08;
uniform float length_scale = 1.0;
uniform float energy = 2.0;
uniform vec4 color_far : source_color = vec4(0.4, 0.1, 0.9, 1.0);
uniform vec4 color_near : source_color = vec4(0.9, 0.75, 1.0, 1.0);

varying float glow;
varying float tint;

void vertex() {
	float ph = fract(TIME * rate + UV.y);
	float r = core + (radius - core) * pow(1.0 - ph, 1.5);
	float ang = UV.x + ph * turns * TAU;
	vec3 radial = vec3(cos(ang), 0.0, sin(ang));
	vec3 tangent = vec3(-sin(ang), 0.0, cos(ang));
	vec3 center = radial * r + vec3(0.0, height * (1.0 - ph) * (1.0 - ph), 0.0);
	float len = (0.25 + r * 0.12) * length_scale;
	// Лента наклонена между плоскостью и вертикалью — видна и сверху, и сбоку
	vec3 side = normalize(radial + vec3(0.0, 1.0, 0.0));
	VERTEX = center + tangent * UV2.x * len + side * UV2.y * width * (0.6 + r * 0.08);
	glow = smoothstep(0.0, 0.2, ph) * (1.0 - smoothstep(0.88, 1.0, ph));
	tint = ph;
}

void fragment() {
	ALBEDO = mix(color_far.rgb, color_near.rgb, tint) * glow * energy;
}
