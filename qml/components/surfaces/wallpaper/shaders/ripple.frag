// Rings spread from the origin, carrying the new wallpaper with them
void main() {
    vec2 uv = qt_TexCoord0;
    vec2 away = (uv - origin) * vec2(aspect, 1.0);
    float dist = length(away);
    float strength = 0.025 * sin(progress * PI);
    vec2 push = dist > 0.0 ? away / dist * sin(dist * 45.0 - progress * 30.0) * strength : vec2(0.0);
    vec2 moved = uv + push / vec2(aspect, 1.0);
    float t = dist / (farthestCorner() + 0.001);
    finish(mix(fromColor(moved), toColor(moved), reveal(t, 0.25)));
}
