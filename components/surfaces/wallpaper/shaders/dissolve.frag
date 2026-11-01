// The new wallpaper burns through in soft patches: everywhere at once, or
// sweeping along the direction or out from the origin
void main() {
    vec2 uv = qt_TexCoord0;
    vec2 p = uv * vec2(aspect, 1.0);
    float n = noise(p * 6.0) * 0.65 + noise(p * 24.0) * 0.25 + hash(floor(p * 400.0)) * 0.1;
    // Sweeping, the patches burn within the band passing over them
    float local = localProgress(uv);
    float s = 0.08;
    float e = local * (1.0 + s);
    finish(mix(fromColor(uv), toColor(uv), 1.0 - smoothstep(e - s, e, n)));
}
