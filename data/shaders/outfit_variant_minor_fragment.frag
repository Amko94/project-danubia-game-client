// Minor variant: flickering fire aura around the sprite.
// Input is the sprite rendered into a framebuffer with an 8px transparent border,
// u_Center holds the framebuffer size in pixels.
uniform mat4 u_Color;
uniform float u_Time;
uniform vec2 u_Center;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
uniform sampler2D u_Tex0;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void main()
{
    vec2 texel = 1.0 / u_Center;
    vec4 base = texture2D(u_Tex0, v_TexCoord);
    float glow = 0.0;
    // Twelve tongues of flame; each has its own flickering reach (2..5.5 px).
    for (int i = 0; i < 12; i++) {
        float ang = float(i) * 0.5236;
        float reach = 2.0 + 3.5 * (0.5 + 0.5 * sin(u_Time * 9.0 + hash(float(i)) * 6.28 + v_TexCoord.y * 40.0));
        for (int j = 1; j <= 4; j++) {
            float d = reach * float(j) / 4.0;
            float a = texture2D(u_Tex0, v_TexCoord + vec2(cos(ang), sin(ang)) * d * texel).a;
            glow = max(glow, a * (1.0 - float(j) / 5.0));
        }
    }
    glow *= 1.0 - base.a;
    float flick = 0.5 + 0.5 * sin(u_Time * 11.0 + v_TexCoord.x * 60.0 + v_TexCoord.y * 30.0);
    vec3 fire = mix(vec3(1.0, 0.15, 0.0), vec3(1.0, 0.8, 0.1), glow * 1.4 * (0.6 + 0.4 * flick));

    // Sprite pixels: slightly heated up. The framebuffer holds premultiplied colour.
    vec3 sprite = base.a > 0.001 ? base.rgb / base.a : vec3(0.0);
    sprite = mix(sprite, sprite * vec3(1.25, 0.9, 0.7) + vec3(0.12, 0.03, 0.0) * flick, 0.5);

    float alpha = base.a + glow * 0.9;
    if (alpha < 0.01) discard;
    vec3 rgb = (sprite * base.a + fire * glow * 0.9) / alpha;
    gl_FragColor = vec4(rgb, alpha);
}
