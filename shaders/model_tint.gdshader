shader_type canvas_item;
// Житель-модель: атлас с белым телом красим в цвет генов (цвет вершин) только там,
// где маска белая, — глаз, рот и румянец остаются своих цветов.

uniform sampler2D mask : filter_linear_mipmap;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	// Маска — только для атласа; тень, сияние и прочее без текстуры — как есть.
	float m = TEXTURE_PIXEL_SIZE.x < 0.5 ? texture(mask, UV).r : 0.0;
	COLOR = vec4(c.rgb * mix(vec3(1.0), tint.rgb, m), c.a * tint.a);
}
