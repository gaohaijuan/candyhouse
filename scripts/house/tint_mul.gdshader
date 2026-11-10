shader_type canvas_item;
render_mode blend_mul;
// Recolours an item's main material: pixels near `ref` in hue (and colourful
// enough) take the hue of `target`, with saturation and brightness scaled by
// target/ref, so shading and highlights stay. Other parts keep their colour.
uniform bool enabled = false;
uniform vec4 ref : source_color = vec4(0.94, 0.42, 0.62, 1.0);
uniform vec4 target : source_color = vec4(0.94, 0.42, 0.62, 1.0);
uniform float hue_range = 0.075;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * clamp(p - 1.0, 0.0, 1.0);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	if (enabled) {
		vec3 h = rgb2hsv(c.rgb);
		vec3 r = rgb2hsv(ref.rgb);
		vec3 t = rgb2hsv(target.rgb);
		float dh = abs(h.x - r.x);
		dh = min(dh, 1.0 - dh);
		float w = (1.0 - smoothstep(hue_range * 0.6, hue_range, dh)) * smoothstep(0.08, 0.2, h.y);
		vec3 n = vec3(t.x, clamp(h.y * t.y / max(r.y, 0.05), 0.0, 1.0), clamp(h.z * t.z / max(r.z, 0.05), 0.0, 1.0));
		c.rgb = mix(c.rgb, hsv2rgb(n), w);
	}
	COLOR = c;
}
