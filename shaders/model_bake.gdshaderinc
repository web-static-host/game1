// Съёмка слоёв гаврика (ModelSprites): узор, жабры, шерсть, волосы, панцирь, рог.
// Подключается в шейдер с render_mode; #define MASK — кадр-маска: ровный albedo без света.
// Координаты позы покоя тела — в UV (x, y) и UV2.x (z), м: узор остаётся на месте в любой позе.
// effect: 0 — сплошной, 1 — полосы, 2 — пятна, 3 — жабры, 4 — шерсть, 5 — волосы,
// 6 — пластины панциря, 7 — кольца рога, 8 — тело без крайних пальцев.

uniform int effect = 0;
uniform vec3 albedo : source_color = vec3(1.0);
// Сдвиг по нормали (м) и добавка к нему на макушке.
uniform float grow = 0.0;
uniform float top_grow = 0.0;
// Шерсть: доля оболочки (0 — у кожи, 1 — кончики).
uniform float shell = 0.0;
// Тело без пальцев: 1 — палец убран (x — Finger1, … w — Finger4).
uniform vec4 hide_fingers = vec4(0.0);
// Жабры: x щелей и высота верхней.
uniform vec2 gill = vec2(0.44, 1.12);

varying vec3 rest;

const vec3 SPOTS[7] = {
	vec3(-0.675, 1.97, 0.135), vec3(0.63, 2.06, 0.11), vec3(-0.405, 1.14, 0.16), vec3(0.45, 1.21, 0.12),
	vec3(0.0, 0.86, 0.09), vec3(-0.7, 1.53, 0.08), vec3(0.7, 1.57, 0.09)
};

// Расстояние до отрезка ab и доля по нему.
vec2 seg(vec3 p, vec3 a, vec3 b) {
	vec3 ab = b - a;
	float t = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
	return vec2(length(p - a - ab * t), t);
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Расстояние до края шестиугольной ячейки (0 — край).
float hex_edge(vec2 p) {
	const vec2 s = vec2(1.0, 1.7320508);
	vec4 hc = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
	vec4 h = vec4(p - hc.xy * s, p - (hc.zw + 0.5) * s);
	vec2 q = dot(h.xy, h.xy) < dot(h.zw, h.zw) ? h.xy : h.zw;
	q = abs(q);
	return 0.5 - max(dot(q, s * 0.5), q.x);
}

void vertex() {
	if (effect == 5 || effect == 7) {
		rest = vec3(UV, 0.0);
	} else {
		rest = vec3(UV, UV2.x);
	}
	VERTEX += NORMAL * (grow + top_grow * smoothstep(1.9, 2.42, UV.y));
}

void fragment() {
	vec3 c = albedo;
	// Насколько красить в цвет (в маске — доля G): 1 — полностью, меньше — светлее.
	float tintk = 1.0;
	float rough = 0.55;
	float spec = 0.35;
	vec2 p = rest.xy;
	bool torso = abs(p.x) < 0.86 && p.y > 0.62 && p.y < 2.39;
	if (effect == 1) {
		// Полосы: четыре волнистые полосы поперёк туловища.
		bool on = false;
		for (int i = 0; i < 4; i++) {
			float y = 2.41 - 1.76 * (0.18 + float(i) * 0.22) + sin(p.x * 4.0) * 0.045;
			on = on || (p.y < y && p.y > y - 0.124);
		}
		if (!torso || !on) {
			discard;
		}
	} else if (effect == 2) {
		// Пятна.
		bool on = false;
		for (int i = 0; i < 7; i++) {
			on = on || distance(p, SPOTS[i].xy) < SPOTS[i].z;
		}
		if (!torso || !on) {
			discard;
		}
	} else if (effect == 3) {
		// Жабры: по три изогнутые щели на каждом боку, выгнуты к середине.
		bool on = false;
		for (int i = 0; i < 3; i++) {
			for (int s = 0; s < 2; s++) {
				float sx = s == 0 ? -1.0 : 1.0;
				vec2 q = (p - vec2(sx * (gill.x + 0.06), gill.y - float(i) * 0.15)) / vec2(0.06, 0.075);
				on = on || (abs(length(q) - 1.0) < 0.42 && q.x * sx < -0.25);
			}
		}
		if (!on || rest.z < 0.0) {
			discard;
		}
	} else if (effect == 4) {
		// Шерсть: волоски — столбики в клетках, к кончикам тоньше и реже.
		// Клочки по ~8 см, к кончикам свисают вниз.
		vec3 q = rest * 13.0 + vec3(0.0, shell * 0.35, 0.0);
		vec3 f = fract(q) - 0.5;
		float n = hash3(floor(q));
		if (length(f) > 0.62 * (1.0 - shell * 0.75) || n < 0.15 + 0.25 * shell) {
			discard;
		}
		// Кисти — без шерсти.
		if (abs(p.x) > 1.1 && p.y < 1.05) {
			discard;
		}
		c *= mix(0.7, 1.0, shell);
	} else if (effect == 5) {
		// Волосы — гладкие матовые лепестки; красим чуть не в полную силу — светлее и мягче тела.
		tintk = 0.9;
		rough = 0.7;
		spec = 0.25;
	} else if (effect == 6) {
		// Панцирь: каёмка вокруг туловища и головы (руки и ноги — без), шестиугольные пластины.
		if ((abs(p.x) > 0.95 && p.y < 2.05) || p.y < 0.55) {
			discard;
		}
		float e = hex_edge(p / 0.25);
		c *= e < 0.07 ? 0.55 : 1.0;
	} else if (effect == 8) {
		// Убранные пальцы (поза покоя, обе руки — по |x|; где пальцы у тела — по прототипу):
		// всё, что дальше корня пальца.
		vec3 q = vec3(abs(rest.x), rest.y, 0.0);
		vec2 d1 = seg(q, vec3(1.08, 0.8, 0.0), vec3(0.93, 0.58, 0.0));
		vec2 d4 = seg(q, vec3(1.5, 0.8, 0.0), vec3(1.64, 0.58, 0.0));
		if ((hide_fingers.x > 0.5 && d1.x < 0.09 && d1.y > 0.15) || (hide_fingers.w > 0.5 && d4.x < 0.09 && d4.y > 0.15)) {
			discard;
		}
	} else if (effect == 7) {
		// Рог: три тёмных кольца у основания.
		float y = rest.y;
		bool ring = abs(y - 0.1) < 0.025 || abs(y - 0.3) < 0.025 || abs(y - 0.5) < 0.022;
		c *= ring ? 0.68 : 1.0;
	}
#ifdef MASK
	ALBEDO = vec3(albedo.r, albedo.g * tintk, albedo.b);
#else
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = spec;
#endif
}
