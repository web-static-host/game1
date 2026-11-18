shader_type canvas_item;
// Превью комнаты: видна только сама комната (hole, в пикселях превью), углы скруглены.
uniform vec2 box_size = vec2(290.0, 150.0);
uniform vec4 hole = vec4(0.0, 0.0, 290.0, 150.0);
uniform float radius = 12.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 p = UV * box_size;
	vec2 half_size = hole.zw * 0.5;
	vec2 q = abs(p - (hole.xy + half_size)) - (half_size - vec2(radius));
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	c.a *= clamp(0.5 - d, 0.0, 1.0);
	COLOR = c;
}
