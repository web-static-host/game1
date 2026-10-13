shader_type canvas_item;
// Небо по высоте: светлое у горизонта → насыщенно-голубое выше → тёмно-синее в стратосфере
// → чёрный космос со звёздами. У земли — холмы вдали и облака (с параллаксом).

uniform float alt_top = 100.0;
uniform float alt_bottom = 0.0;
// 1 — день, 0 — ночь.
uniform float daylight = 1.0;
// Зимой небо бледное, холмы и облака светлее.
uniform float winter = 0.0;
// Камера по x (в клетках), ширина экрана в клетках, высота земли у базы.
uniform float cam_x = 0.0;
uniform float view_w = 60.0;
uniform float ground_alt = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	float alt = mix(alt_top, alt_bottom, UV.y);
	float above = alt - ground_alt;
	vec3 horizon = mix(vec3(0.72, 0.9, 1.0), vec3(0.88, 0.91, 0.95), winter);
	vec3 low = mix(vec3(0.2, 0.6, 0.94), vec3(0.52, 0.64, 0.8), winter);
	vec3 mid = vec3(0.2, 0.38, 0.78);
	vec3 high = vec3(0.04, 0.07, 0.2);
	vec3 space = vec3(0.0, 0.0, 0.02);
	vec3 c = mix(horizon, low, smoothstep(0.0, 40.0, above));
	c = mix(c, mid, smoothstep(200.0, 12000.0, alt));
	c = mix(c, high, smoothstep(9000.0, 35000.0, alt));
	c = mix(c, space, smoothstep(50000.0, 100000.0, alt));

	// Облака: пухлые пятна шума в полосе над землёй, медленно плывут.
	float cx = cam_x * 0.25 + (UV.x - 0.5) * view_w + TIME * 0.25;
	float band = smoothstep(5.0, 8.0, above) * (1.0 - smoothstep(18.0, 22.0, above));
	float n = noise(vec2(cx / 7.0, above / 3.0)) * 0.65 + noise(vec2(cx / 2.5, above / 1.4)) * 0.35;
	float cloud = smoothstep(0.62, 0.68, n) * band;
	float under = smoothstep(0.62, 0.68, noise(vec2(cx / 7.0, (above + 0.6) / 3.0)) * 0.65 + noise(vec2(cx / 2.5, (above + 0.6) / 1.4)) * 0.35) * band;
	vec3 cloud_col = mix(vec3(0.78, 0.86, 0.97), vec3(1.0), cloud - under * 0.0);
	c = mix(c, vec3(0.8, 0.87, 0.97), (under - cloud * 0.0) * (1.0 - cloud) * 0.9);
	c = mix(c, cloud_col, cloud);

	// Холмы вдали: два слоя с параллаксом.
	float hx1 = cam_x * 0.35 + (UV.x - 0.5) * view_w;
	float h1 = ground_alt + 5.0 + 3.0 * sin(hx1 / 9.0) + 1.5 * sin(hx1 / 3.7 + 1.0);
	float hx2 = cam_x * 0.55 + (UV.x - 0.5) * view_w;
	float h2 = ground_alt + 2.5 + 2.5 * sin(hx2 / 6.0 + 2.0) + 1.2 * sin(hx2 / 2.3);
	vec3 far_col = mix(vec3(0.6, 0.83, 0.56), vec3(0.84, 0.89, 0.94), winter);
	vec3 near_col = mix(vec3(0.47, 0.77, 0.43), vec3(0.91, 0.94, 0.97), winter);
	c = mix(c, far_col, step(alt, h1));
	c = mix(c, near_col, step(alt, h2));

	// Ночь: небо тёмно-синее.
	vec3 night = vec3(0.02, 0.04, 0.12) + c * 0.08;
	c = mix(night, c, daylight);
	float star = step(0.997, hash(floor(FRAGCOORD.xy / 2.0)));
	c += vec3(star) * max(smoothstep(30000.0, 90000.0, alt), (1.0 - daylight) * 0.8) * 0.9;
	COLOR = vec4(c, 1.0);
}
