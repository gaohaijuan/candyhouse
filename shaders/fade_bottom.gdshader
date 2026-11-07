shader_type canvas_item;
// Fades the bottom `fade` pixels of a rect of height `h` (used to blend one
// map landscape into the next).
uniform float h = 1000.0;
uniform float fade = 240.0;
varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	COLOR.a *= 1.0 - smoothstep(h - fade, h, local.y);
}
