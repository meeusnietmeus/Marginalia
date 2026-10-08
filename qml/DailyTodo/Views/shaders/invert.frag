#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};
layout(binding = 1) uniform sampler2D source;

// Dark mode for PDF pages: invert, then rotate the hue by 180 degrees so colours (images,
// highlights) keep roughly their hue while white paper turns dark and black text turns light.
void main() {
    vec3 c = vec3(1.0) - texture(source, qt_TexCoord0).rgb;
    vec3 rotated = vec3(
        dot(c, vec3(-0.574, 1.430, 0.144)),
        dot(c, vec3( 0.426, 0.430, 0.144)),
        dot(c, vec3( 0.426, 1.430, -0.856)));
    // Lift the blacks slightly so the page matches the app's dark brown instead of pure black.
    vec3 outColor = clamp(rotated, 0.0, 1.0) * 0.82 + vec3(0.12, 0.09, 0.06);
    fragColor = vec4(outColor, 1.0) * qt_Opacity;
}
