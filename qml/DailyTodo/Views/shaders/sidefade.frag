#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float shift;       // how far the content has slid, as a share of the column's width
    float alignRight;  // 1: the column sits at the right edge of the window (it fades to the right)
    float amount;      // 1: fully faded (at rest), 0: no fade at all (revealed)
};
layout(binding = 1) uniform sampler2D source;

// A side column at rest: its content fades out towards the outer edge of the window. The fade is
// pinned to the column, not to the content sliding inside it.
void main() {
    vec4 c = texture(source, qt_TexCoord0);
    float x = qt_TexCoord0.x + shift;                 // across the column: 0 left, 1 right
    float visible = clamp(alignRight > 0.5 ? 1.0 - x : x, 0.0, 1.0);
    fragColor = c * mix(1.0, visible, amount) * qt_Opacity;
}
