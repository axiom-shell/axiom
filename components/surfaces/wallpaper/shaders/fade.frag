// The new wallpaper fades in over the old
void main() {
    vec2 uv = qt_TexCoord0;
    finish(mix(fromColor(uv), toColor(uv), progress));
}
