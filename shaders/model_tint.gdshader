shader_type canvas_item;
// Житель-модель. Лист ModelSprites: слева кадры (тело белое на сером фоне), справа маска тех же
// кадров: R — силуэт (прозрачность), G — где красить в цвет (цвет вершин: тела или волос);
// глаз, рот, рог — как есть.

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (TEXTURE_PIXEL_SIZE.x < 0.5) {
		vec3 m = texture(TEXTURE, UV + vec2(0.5, 0.0)).rgb;
		COLOR = vec4(c.rgb * mix(vec3(1.0), tint.rgb, m.g), m.r * tint.a);
	} else {
		// Тень, сияние и прочее без атласа — обычным цветом.
		COLOR = c * tint;
	}
}
