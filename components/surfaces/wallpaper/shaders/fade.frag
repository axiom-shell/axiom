// The new wallpaper fades in over the old: everywhere at once, or in a
// wide soft band sweeping along the direction or out from the origin
void main() {
    vec2 uv = qt_TexCoord0;
    finish(mix(fromColor(uv), toColor(uv), localProgress(uv)));
}
