shader_type canvas_item;
// Небо по высоте: голубое у земли → тёмно-синее в стратосфере → чёрный космос со звёздами.

uniform float alt_top = 100.0;
uniform float alt_bottom = 0.0;
// 1 — день, 0 — ночь.
uniform float daylight = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float alt = mix(alt_top, alt_bottom, UV.y);
	vec3 low = vec3(0.58, 0.78, 0.96);
	vec3 mid = vec3(0.2, 0.38, 0.78);
	vec3 high = vec3(0.04, 0.07, 0.2);
	vec3 space = vec3(0.0, 0.0, 0.02);
	vec3 c = mix(low, mid, smoothstep(0.0, 12000.0, alt));
	c = mix(c, high, smoothstep(9000.0, 35000.0, alt));
	c = mix(c, space, smoothstep(50000.0, 100000.0, alt));
	// Ночь: небо тёмно-синее.
	vec3 night = vec3(0.02, 0.04, 0.12) + c * 0.08;
	c = mix(night, c, daylight);
	float star = step(0.997, hash(floor(FRAGCOORD.xy / 2.0)));
	c += vec3(star) * max(smoothstep(30000.0, 90000.0, alt), (1.0 - daylight) * 0.8) * 0.9;
	COLOR = vec4(c, 1.0);
}
