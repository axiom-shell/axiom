// Diamond tiles open across the screen in the direction
void main() {
    vec2 uv = qt_TexCoord0;
    float tiles = 10.0;
    vec2 p = uv * vec2(aspect, 1.0) * tiles;
    vec2 cell = floor(p);
    vec2 f = fract(p) - 0.5;
    vec2 center = (cell + 0.5) / tiles / vec2(aspect, 1.0);
    float diamond = abs(f.x) + abs(f.y);
    finish(mix(fromColor(uv), toColor(uv), reveal(clamp(along(center), 0.0, 1.0) * 0.6 + diamond * 0.4, 0.03)));
}
