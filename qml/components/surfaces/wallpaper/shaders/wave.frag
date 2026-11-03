// A wipe whose edge is a moving wave
void main() {
    vec2 uv = qt_TexCoord0;
    vec2 d = direction();
    float across = dot((uv - 0.5) * vec2(aspect, 1.0), vec2(-d.y, d.x));
    float amp = 0.035;
    float t = along(uv) + sin(across * 18.0 + progress * 9.0) * amp + amp;
    finish(mix(fromColor(uv), toColor(uv), reveal(t / (1.0 + 2.0 * amp), 0.03)));
}
