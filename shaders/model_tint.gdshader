shader_type canvas_item;
// Житель-модель. Атлас — белое тело на сером фоне; маска: R — силуэт (прозрачность),
// G — где тело. Тело красим в цвет генов (цвет вершин), глаз, рот и румянец — как есть.

uniform sampler2D mask : filter_linear_mipmap;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (TEXTURE_PIXEL_SIZE.x < 0.5) {
		vec3 m = texture(mask, UV).rgb;
		COLOR = vec4(c.rgb * mix(vec3(1.0), tint.rgb, m.g), m.r * tint.a);
	} else {
		// Тень, сияние и прочее без атласа — обычным цветом.
		COLOR = c * tint;
	}
}
