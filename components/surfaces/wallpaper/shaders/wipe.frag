// A soft straight edge sweeps across in the direction
void main() {
    vec2 uv = qt_TexCoord0;
    finish(mix(fromColor(uv), toColor(uv), reveal(along(uv), 0.06)));
}
