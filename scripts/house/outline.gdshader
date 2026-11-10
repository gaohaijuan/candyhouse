shader_type canvas_item;
// Glow ring around a sprite's painted pixels, for the picked piece in the
// candy house: drawn by a copy of the sprite laid over it, so the piece's own
// recolour material stays untouched. A white line hugs the edge and a warm
// gold band sits outside it.

uniform vec4 glow_color : source_color = vec4(1.0, 0.78, 0.18, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 1.0, 0.92, 1.0);
uniform float width = 10.0;   // gold band width in texture pixels

float reach(sampler2D tex, vec2 uv, vec2 px, float w) {
	float m = 0.0;
	for (int i = 0; i < 16; i++) {
		float ang = float(i) * 6.2831853 / 16.0;
		vec2 dir = vec2(cos(ang), sin(ang)) * px;
		m = max(m, texture(tex, uv + dir * w).a);
		m = max(m, texture(tex, uv + dir * w * 0.5).a);
	}
	return m;
}

void fragment() {
	float a = texture(TEXTURE, UV).a;
	float outer = clamp(reach(TEXTURE, UV, TEXTURE_PIXEL_SIZE, width) - a, 0.0, 1.0);
	float inner = clamp(reach(TEXTURE, UV, TEXTURE_PIXEL_SIZE, width * 0.35) - a, 0.0, 1.0);
	vec3 c = mix(glow_color.rgb, edge_color.rgb, inner);
	COLOR = vec4(c, outer);
}
