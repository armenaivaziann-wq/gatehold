shader_type spatial;
// Пустынный жук орды: шесть ног ходят двумя тройками в противофазе, тело чуть покачивается,
// глаза светятся, оттенок панциря у каждого свой.
// INSTANCE_CUSTOM: x — фаза шага, y — насколько быстро идёт (0 — стоит);
// у живых z, w — скорость по земле (x, z): между шагами расчёта орды жук сдвигается на
// скорость × lag; у трупиков (corpse) w — время смерти по TIME: лапы поджаты, глаза погасли,
// трупик лежит, потом за несколько секунд уходит в песок.
// UV.x — метка вершины: 0 тело, 1 и 2 — две тройки ног, 3 — глаза.
// Цвета вершин — уже в линейном пространстве.

render_mode cull_back;

uniform bool corpse = false;
uniform float lag = 0.0;

varying float eye;
varying float kind;

const float LIE_TIME = 14.0;

varying float dead;

void vertex() {
	// Вид врага — в сотнях фазы: 0 обычный, 1 бегун, 2 громила, 3 босс (большой — шагает реже)
	kind = floor(INSTANCE_CUSTOM.x / 100.0);
	float phase = INSTANCE_CUSTOM.x - kind * 100.0;
	float t = TIME * 15.0 / (kind > 2.5 && kind < 3.5 ? 2.2 : 1.0) + phase;
	float moving = INSTANCE_CUSTOM.y;
	float tag = UV.x;
	dead = corpse ? 1.0 : 0.0;
	if (dead > 0.5) {
		float age = TIME - INSTANCE_CUSTOM.w;
		if (tag > 0.5 && tag < 2.5) {
			// Лапы поджаты к телу и дёргаются первые полсекунды
			float lift = clamp(1.0 - VERTEX.y / 0.45, 0.0, 1.0);
			VERTEX.x *= mix(1.0, 0.55, lift);
			VERTEX.y += lift * (0.16 + sin(TIME * 40.0 + tag * 3.0) * 0.04 * clamp(1.0 - age * 2.0, 0.0, 1.0));
		}
		// Тело перевёрнуто: локальная +Y смотрит в землю — по ней и уходим в песок
		VERTEX.y += max(age - LIE_TIME, 0.0) * 0.12;
	} else if (tag > 0.5 && tag < 2.5) {
		float ph = tag < 1.5 ? 0.0 : PI;
		// Кончик ноги (внизу) ходит сильнее колена
		float lift = clamp(1.0 - VERTEX.y / 0.45, 0.0, 1.0);
		VERTEX.z += sin(t + ph) * 0.16 * moving * lift;
		VERTEX.y += max(0.0, cos(t + ph)) * 0.07 * moving * lift;
	} else {
		VERTEX.y += sin(t * 2.0) * 0.015 * moving;
		VERTEX.x += sin(t) * 0.012 * moving;
	}
	if (!corpse) {
		// Мировой сдвиг → локальный: модельная матрица — поворот × равномерный масштаб
		vec3 shift = vec3(INSTANCE_CUSTOM.z, 0.0, INSTANCE_CUSTOM.w) * lag;
		float s2 = dot(MODEL_MATRIX[0].xyz, MODEL_MATRIX[0].xyz);
		VERTEX += transpose(mat3(MODEL_MATRIX)) * shift / s2;
	}
	eye = step(2.5, tag) * (1.0 - step(0.5, dead));
	float tint = 0.8 + 0.4 * fract(phase * 7.31);
	// Бегуны — песочные, громилы — тёмно-красные, босс — почти чёрный с красными глазами
	// 0 обычный, 1 бегун, 2 громила, 3 босс, 4 обычный в доспехах (стальной)
	vec3 kind_col = kind < 0.5 ? vec3(1.0) : (kind < 1.5 ? vec3(1.4, 1.15, 0.75) : (kind < 2.5 ? vec3(0.95, 0.45, 0.35) :
		(kind < 3.5 ? vec3(0.5, 0.3, 0.3) : vec3(1.0))));
	if (kind > 3.5) {
		// Доспехи: панцирь отливает сталью
		COLOR.rgb = mix(COLOR.rgb, vec3(0.16, 0.18, 0.23), 0.6);
	}
	COLOR.rgb *= mix(vec3(tint) * kind_col, vec3(1.0), eye);
	if (kind > 2.5 && kind < 3.5 && eye > 0.5) {
		COLOR.rgb = vec3(1.0, 0.15, 0.08);
	}
	COLOR.rgb *= mix(1.0, 0.5, step(0.5, dead));
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.55;
	SPECULAR = 0.4;
	EMISSION = COLOR.rgb * eye * 2.5;
}
