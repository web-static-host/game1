shader_type spatial;
render_mode cull_disabled;
// Тело модели с текстурой (ModelSprites, модели TEXTURED). Тело в текстуре жёлто-оранжевое:
// его делаем белым с той же светотенью (цвет даст игра по маске), остальное — как в текстуре.
// mask — кадр-маска (свет выключен): R — силуэт, G — тело.

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform bool mask = false;

varying vec2 tuv;
varying float rest_y;

void vertex() {
	tuv = CUSTOM0.xy;
	// Высота точки в позе покоя (м): тёмные подошвы в текстуре — тоже тело.
	rest_y = UV.y;
}

vec3 hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

void fragment() {
	vec3 c = texture(tex, tuv).rgb;
	vec3 h = hsv(c);
	// Значения линейные: жёлто-оранжевое тело — тон 0.03–0.25, насыщенное, не тёмное.
	float body = smoothstep(0.02, 0.04, h.x) * (1.0 - smoothstep(0.24, 0.26, h.x))
		* smoothstep(0.45, 0.55, h.y) * smoothstep(0.15, 0.25, h.z);
	body = max(body, (1.0 - smoothstep(0.1, 0.14, rest_y)) * (1.0 - smoothstep(0.2, 0.3, h.z)));
	if (mask) {
		ALBEDO = vec3(0.0);
		EMISSION = vec3(1.0, body, 0.0);
	} else {
		float shade = max(h.z / 0.95, 0.85) * 0.92;
		ALBEDO = mix(c, vec3(shade), body);
		ROUGHNESS = 0.6;
		SPECULAR = 0.35;
	}
}
