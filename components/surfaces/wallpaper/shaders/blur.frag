// The old wallpaper blurs away and the new one comes into focus:
// everywhere at once, or sweeping along the direction or out from the origin
void main() {
    vec2 uv = qt_TexCoord0;
    float local = localProgress(uv);
    float radius = 0.025 * sin(local * PI);
    float m = smoothstep(0.3, 0.7, local);
    vec4 sum = vec4(0.0);
    float total = 0.0;
    // A spiral of taps over a disc
    for (int i = 0; i < 24; i++) {
        float f = float(i) / 24.0;
        float a = float(i) * 2.39996;
        vec2 o = vec2(cos(a), sin(a)) * sqrt(f) * radius * vec2(1.0 / aspect, 1.0);
        float w = 1.0 - f * 0.5;
        sum += mix(fromColor(uv + o), toColor(uv + o), m) * w;
        total += w;
    }
    finish(sum / total);
}
