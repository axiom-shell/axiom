// Slats turn over one after another in the direction
void main() {
    vec2 uv = qt_TexCoord0;
    float slats = 12.0;
    float t = along(uv);
    float slat = floor(t * slats) / slats;
    float within = fract(t * slats);
    // Each slat starts a little after the one before
    finish(mix(fromColor(uv), toColor(uv), reveal(slat * 0.5 + within * 0.5, 0.05)));
}
