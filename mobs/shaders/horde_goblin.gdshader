shader_type spatial;
// Гоблин орды: ноги шагают от бедра, руки машут в противофазе, тело подпрыгивает на шаге,
// глаза светятся, оттенок кожи у каждого свой.
// INSTANCE_CUSTOM: x — фаза шага, y — насколько быстро идёт (0 — стоит);
// у живых z, w — скорость по земле (x, z): между шагами расчёта орды гоблин сдвигается на
// скорость × lag; у трупов (corpse; лежит навзничь, локальная +Z смотрит вверх) w — время
// смерти по TIME: труп лежит, потом за несколько секунд уходит в землю.
// UV.x — метка вершины: 0 тело, 1 и 2 — левая и правая нога, 3 — глаза, 4 и 5 — руки.
// Вид 4 — обычный в доспехах: рубаха, пояс и штаны стальные, на макушке шлем.
// Цвета вершин — уже в линейном пространстве.

render_mode cull_back;

// Высота тазобедренного и плечевого сустава, низ шлема — у каждого двуногого свои (mobs.gd: RIGS)
uniform float hip = 0.46;
uniform float shoulder = 0.72;
uniform float helmet_y = 0.935;
uniform float helmet_x = 0.15;
const float LIE_TIME = 14.0;

uniform bool corpse = false;
uniform float lag = 0.0;

varying float eye;
varying float kind;
varying float dead;

// Повернуть вершину вокруг оси X, проходящей через точку (y, z) = pivot
vec3 swing(vec3 v, vec2 pivot, float angle) {
	vec2 d = vec2(v.y, v.z) - pivot;
	float c = cos(angle);
	float s = sin(angle);
	return vec3(v.x, pivot.x + d.x * c - d.y * s, pivot.y + d.x * s + d.y * c);
}

void vertex() {
	// Вид врага — в сотнях фазы: 0 обычный, 1 бегун, 2 громила, 3 босс (большой — шагает реже)
	kind = floor(INSTANCE_CUSTOM.x / 100.0);
	float phase = INSTANCE_CUSTOM.x - kind * 100.0;
	float t = TIME * 9.0 / (kind > 2.5 && kind < 3.5 ? 2.2 : 1.0) + phase;
	float moving = min(INSTANCE_CUSTOM.y, 1.3);
	float tag = UV.x;
	vec3 rest = VERTEX;
	dead = corpse ? 1.0 : 0.0;
	bool leg = tag > 0.5 && tag < 2.5;
	bool arm = tag > 3.5;
	if (dead > 0.5) {
		float age = TIME - INSTANCE_CUSTOM.w;
		// Руки и ноги раскинуты и дёргаются первые полсекунды
		if (leg || arm) {
			float side = tag < 1.5 || (tag > 3.5 && tag < 4.5) ? -1.0 : 1.0;
			VERTEX.x += side * 0.06 + sin(TIME * 35.0 + tag) * 0.02 * clamp(1.0 - age * 2.0, 0.0, 1.0);
		}
		VERTEX.z -= max(age - LIE_TIME, 0.0) * 0.12;
	} else {
		if (leg) {
			float ph = tag < 1.5 ? 0.0 : PI;
			VERTEX = swing(VERTEX, vec2(hip, 0.0), sin(t + ph) * 0.6 * moving);
			// Ступня приподнимается, когда нога идёт вперёд
			float low = clamp((hip - VERTEX.y) / hip, 0.0, 1.0);
			VERTEX.y += max(0.0, -cos(t + ph)) * 0.07 * moving * low;
		} else if (arm) {
			// Левая рука — с правой ногой, правая — с левой
			float ph = tag < 4.5 ? PI : 0.0;
			VERTEX = swing(VERTEX, vec2(shoulder, 0.02), sin(t + ph) * 0.5 * moving);
		}
		// Подпрыгивает на каждом шаге и чуть раскачивается
		VERTEX.y += abs(sin(t)) * 0.035 * moving;
		VERTEX.x += sin(t) * 0.015 * moving * VERTEX.y;
	}
	if (!corpse) {
		// Мировой сдвиг → локальный: модельная матрица — поворот × равномерный масштаб
		vec3 shift = vec3(INSTANCE_CUSTOM.z, 0.0, INSTANCE_CUSTOM.w) * lag;
		float s2 = dot(MODEL_MATRIX[0].xyz, MODEL_MATRIX[0].xyz);
		VERTEX += transpose(mat3(MODEL_MATRIX)) * shift / s2;
	}
	eye = step(2.5, tag) * step(tag, 3.5) * (1.0 - step(0.5, dead));
	float tint = 0.8 + 0.4 * fract(phase * 7.31);
	// Бегуны — светлее и желтее, громилы — тёмные бурые, босс — почти чёрный с красными глазами
	// 0 обычный, 1 бегун, 2 громила, 3 босс, 4 обычный в доспехах (стальной)
	vec3 kind_col = kind < 0.5 ? vec3(1.0) : (kind < 1.5 ? vec3(1.25, 1.2, 0.7) : (kind < 2.5 ? vec3(0.7, 0.55, 0.45) :
		(kind < 3.5 ? vec3(0.45, 0.32, 0.3) : vec3(1.0))));
	if (kind > 3.5) {
		// Доспехи: всё не-кожаное на теле и ногах — сталь; верх головы — шлем
		bool skin = COLOR.g > COLOR.r * 1.3;
		bool helmet = tag < 0.5 && rest.y > helmet_y && abs(rest.x) < helmet_x;
		if ((tag < 2.5 && !skin) || helmet) {
			// Тёмное железо; нагрудник и шлем чуть светлее штанов
			COLOR.rgb = vec3(0.13, 0.15, 0.19) * (1.0 + 0.45 * step(0.52, rest.y));
		}
	}
	COLOR.rgb *= mix(vec3(tint) * kind_col, vec3(1.0), eye);
	if (kind > 2.5 && kind < 3.5 && eye > 0.5) {
		COLOR.rgb = vec3(1.0, 0.15, 0.08);
	}
	COLOR.rgb *= mix(1.0, 0.55, step(0.5, dead));
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	EMISSION = COLOR.rgb * eye * 2.5;
}
