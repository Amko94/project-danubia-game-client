// Major variant: pitch-black flames around a blackened (still readable) sprite with glowing red eyes.
// Input is the sprite rendered into a framebuffer with an 8px transparent border,
// u_Center holds the framebuffer size in pixels.
uniform mat4 u_Color;
uniform float u_Time;
uniform vec2 u_Center;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
uniform sampler2D u_Tex0;

float hash(float n) { return fract(sin(n) * 43758.5453); }
float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

void main()
{
    vec2 texel = 1.0 / u_Center;
    vec4 base = texture2D(u_Tex0, v_TexCoord);
    float glow = 0.0;
    // Twelve tongues of flame; each has its own flickering reach (2..5.5 px).
    for (int i = 0; i < 12; i++) {
        float ang = float(i) * 0.5236;
        float reach = 2.0 + 3.5 * (0.5 + 0.5 * sin(u_Time * 8.0 + hash(float(i) + 3.0) * 6.28 + v_TexCoord.y * 40.0));
        for (int j = 1; j <= 4; j++) {
            float d = reach * float(j) / 4.0;
            float a = texture2D(u_Tex0, v_TexCoord + vec2(cos(ang), sin(ang)) * d * texel).a;
            glow = max(glow, a * (1.0 - float(j) / 5.0));
        }
    }
    glow *= 1.0 - base.a;
    float flick = 0.5 + 0.5 * sin(u_Time * 10.0 + v_TexCoord.x * 60.0 + v_TexCoord.y * 30.0);
    // Dense near the sprite = glowing red, thin outer tips = black smoke.
    float heat = clamp(glow * 1.6, 0.0, 1.0);
    vec3 flame = mix(vec3(0.0, 0.0, 0.0), vec3(0.07, 0.0, 0.01), heat * (0.7 + 0.3 * flick));

    vec3 sprite = base.a > 0.001 ? base.rgb / base.a : vec3(0.0);

    // Eyes (heuristic): tiny spots much brighter than their surroundings turn glowing red.
    float ring = 0.0;
    ring += luma(texture2D(u_Tex0, v_TexCoord + vec2( 2.0, 0.0) * texel).rgb);
    ring += luma(texture2D(u_Tex0, v_TexCoord + vec2(-2.0, 0.0) * texel).rgb);
    ring += luma(texture2D(u_Tex0, v_TexCoord + vec2(0.0,  2.0) * texel).rgb);
    ring += luma(texture2D(u_Tex0, v_TexCoord + vec2(0.0, -2.0) * texel).rgb);
    ring *= 0.25;
    float lum = luma(sprite);
    float eye = base.a > 0.5 ? smoothstep(0.18, 0.4, lum - ring) * smoothstep(0.45, 0.65, lum) : 0.0;

    // Near-black body: desaturate and darken but keep the contrast so the sprite stays readable.
    sprite = mix(sprite, vec3(luma(sprite)), 0.6) * 0.38 + vec3(0.02);
    sprite = mix(sprite, vec3(1.0, 0.05, 0.02) * (1.2 + 0.4 * flick), eye);

    float alpha = base.a + glow * 0.95;
    if (alpha < 0.01) discard;
    vec3 rgb = (sprite * base.a + flame * glow * 0.95) / alpha;
    gl_FragColor = vec4(rgb, alpha);
}
