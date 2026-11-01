// The new wallpaper pushes the old one off the screen in the direction
void main() {
    vec2 uv = qt_TexCoord0;
    vec2 d = direction();
    vec2 old = uv - d * progress;
    if (progress < 1.0 && old.x >= 0.0 && old.y >= 0.0 && old.x <= 1.0 && old.y <= 1.0)
        finish(fromColor(old));
    else
        finish(toColor(uv - d * (progress - 1.0)));
}
