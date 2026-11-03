// The old wallpaper rushes past while the new one settles into place
void main() {
    vec2 uv = qt_TexCoord0;
    vec2 old = origin + (uv - origin) / (1.0 + progress * 0.6);
    vec2 next = origin + (uv - origin) / (1.0 + (1.0 - progress) * 0.25);
    finish(mix(fromColor(old), toColor(next), smoothstep(0.0, 1.0, progress)));
}
