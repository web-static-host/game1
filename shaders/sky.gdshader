shader_type canvas_item;
// Небо по высоте: светлое у горизонта → насыщенно-голубое выше → тёмно-синее в стратосфере
// → чёрный космос со звёздами. У земли — слои-картинки с параллаксом (assets/background/):
// горы, облака, далёкий лес в дымке, холмы. Слой повторяется кусками; вариант куска
// и отражение — от номера куска и сида мира (края всех вариантов сшиты, см. art_src/backgrounds).

uniform float alt_top = 100.0;
uniform float alt_bottom = 0.0;
// 1 — день, 0 — ночь.
uniform float daylight = 1.0;
// Зимой небо бледное, горы и холмы светлее.
uniform float winter = 0.0;
// Камера по x (в клетках), ширина экрана в клетках, высота земли у базы.
uniform float cam_x = 0.0;
uniform float view_w = 60.0;
uniform float ground_alt = 0.0;
// Сид мира (0..999) — порядок кусков слоёв.
uniform float world_seed = 0.0;
// Оттенок неба другой планеты (на Земле — белый).
uniform vec3 tint = vec3(1.0);

uniform sampler2D mountains_1 : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D mountains_2 : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D forest_1 : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D forest_2 : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D hills_1 : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D hills_2 : source_color, filter_linear_mipmap, repeat_disable;
// Атлас из 5 облаков в ряд.
uniform sampler2D clouds : source_color, filter_linear_mipmap, repeat_disable;

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

float h01(float i, float salt) {
	return hash(vec2(i * 0.6180339 + salt * 17.13, world_seed * 0.731 + salt * 3.7));
}

// Размеры кусков: высота картинки / ширина (1199 px); низ картинки продлён ровным цветом
// (prepare.py, PAD), поэтому основание сдвинуто вниз на эту добавку.

// Кусок слоя под пикселем: xy — uv в картинке (u уже отражён), z — вариант (0/1),
// w — 0, если пиксель выше картинки. g — непрерывные координаты для textureGrad
// (без скачка на стыке кусков, иначе на шве берётся мелкий мип и видна линия).
vec4 layer_uv(float lx, float above, float tile_w, float base, float tile_h, float salt, float nvar, bool mirror_ok, out vec2 g) {
	float t = lx / tile_w;
	float ti = floor(t);
	float u = t - ti;
	float variant = min(nvar - 1.0, floor(h01(ti, salt) * nvar));
	if (mirror_ok && h01(ti + 0.5, salt + 5.0) > 0.5) {
		u = 1.0 - u;
	}
	float v = 1.0 - (above - base) / tile_h;
	g = vec2(t, -above / tile_h);
	return vec4(u, clamp(v, 0.0, 1.0), variant, step(0.0, v));
}

// Слой поверх цвета: дымка к горизонту, зимой светлее и бледнее.
vec3 over(vec3 c, vec4 tex, float haze, vec3 horizon, inout float cover) {
	vec3 col = mix(tex.rgb, horizon, haze);
	float l = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, mix(vec3(l), vec3(0.9, 0.93, 0.98), 0.55) * 1.08, winter * 0.75);
	cover = max(cover, tex.a);
	return mix(c, col, tex.a);
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

	float px = (UV.x - 0.5) * view_w;
	float cover = 0.0;
	vec2 g;
	vec4 q;
	vec4 tex;

	// Горы: кусок 36 клеток, низ чуть под землёй, параллакс 0.15.
	// Производные — вне ветвлений: внутри них на мобильных GPU они не определены.
	q = layer_uv(cam_x * 0.15 + px, above, 36.0, -2.0 - 36.0 * 145.0 / 1199.0, 36.0 * 630.0 / 1199.0, 1.0, 2.0, true, g);
	vec2 dx = dFdx(g), dy = dFdy(g);
	if (q.w > 0.0) {
		tex = q.z < 0.5 ? textureGrad(mountains_1, q.xy, dx, dy) : textureGrad(mountains_2, q.xy, dx, dy);
		c = over(c, tex, 0.12, horizon, cover);
	}

	// Облака: слоты по 30 клеток, в слоте одно облако (или пусто), плывут.
	float cx = cam_x * 0.1 + px + TIME * 0.25;
	float si = floor(cx / 30.0);
	float cw = 8.0 + h01(si, 22.0) * 4.0;
	float ch = cw * 160.0 / 384.0;
	vec2 cg = vec2(cx / cw / 5.0, -above / ch);
	vec2 cdx = dFdx(cg), cdy = dFdy(cg);
	if (h01(si, 20.0) < 0.7) {
		float k = floor(h01(si, 21.0) * 4.999);
		float off = h01(si, 23.0) * (30.0 - cw);
		float cy = 8.0 + h01(si, 24.0) * 5.0;
		float u = (cx - si * 30.0 - off) / cw;
		float v = 1.0 - (above - cy) / ch;
		if (u >= 0.0 && u <= 1.0 && v >= 0.0 && v <= 1.0) {
			if (h01(si, 25.0) > 0.5) {
				u = 1.0 - u;
			}
			tex = textureGrad(clouds, vec2((k + u) / 5.0, v), cdx, cdy);
			c = over(c, tex, 0.0, horizon, cover);
		}
	}

	// Далёкий лес в дымке: кусок 30 клеток, параллакс 0.3.
	q = layer_uv(cam_x * 0.3 + px, above, 30.0, 1.0 - 30.0 * 49.0 / 1199.0, 30.0 * 214.0 / 1199.0, 2.0, 2.0, true, g);
	dx = dFdx(g);
	dy = dFdy(g);
	if (q.w > 0.0) {
		tex = q.z < 0.5 ? textureGrad(forest_1, q.xy, dx, dy) : textureGrad(forest_2, q.xy, dx, dy);
		c = over(c, tex, 0.3, horizon, cover);
	}

	// Холмы: кусок 30 клеток, параллакс 0.45.
	q = layer_uv(cam_x * 0.45 + px, above, 30.0, -4.0 - 30.0 * 104.0 / 1199.0, 30.0 * 452.0 / 1199.0, 3.0, 2.0, true, g);
	dx = dFdx(g);
	dy = dFdy(g);
	if (q.w > 0.0) {
		tex = q.z < 0.5 ? textureGrad(hills_1, q.xy, dx, dy) : textureGrad(hills_2, q.xy, dx, dy);
		c = over(c, tex, 0.0, horizon, cover);
	}

	c *= tint;
	// Ночь: небо тёмно-синее.
	vec3 night = vec3(0.02, 0.04, 0.12) + c * mix(0.08, 0.14, cover);
	c = mix(night, c, daylight);
	float star = step(0.997, hash(floor(FRAGCOORD.xy / 2.0)));
	c += vec3(star) * (1.0 - cover) * max(smoothstep(30000.0, 90000.0, alt), (1.0 - daylight) * 0.8) * 0.9;
	COLOR = vec4(c, 1.0);
}
