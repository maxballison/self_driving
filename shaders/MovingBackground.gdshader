shader_type spatial;
render_mode unshaded;

uniform vec4 deep_color : source_color = vec4(0.05, 0.07, 0.12, 1.0);
uniform vec4 mid_color : source_color = vec4(0.08, 0.12, 0.18, 1.0);
uniform vec4 highlight_color : source_color = vec4(0.12, 0.18, 0.25, 1.0);
uniform float flow_speed : hint_range(0.01, 0.5) = 0.08;
uniform float pattern_scale : hint_range(1.0, 10.0) = 4.0;
uniform float noise_scale : hint_range(1.0, 20.0) = 10.0;
uniform float distortion_strength : hint_range(0.0, 2.0) = 0.8;
uniform float ridge_sharpness : hint_range(0.1, 5.0) = 1.5;

// Simplex noise functions

// Permutation polynomial: (34x^2 + x) mod 289
vec3 permute(vec3 x) {
    return mod((34.0 * x + 1.0) * x, 289.0);
}

vec2 cellular2x2(vec2 P) {
    // Cell coordinates
    vec2 Pi = floor(P);
    vec2 Pf = P - Pi;

    // Surrounding points
    vec4 Pt = vec4(Pi.xy, Pi.xy + 1.0);

    // Hash values
    Pt = mod(Pt, 289.0);
    Pt = mod((34.0 * Pt + 1.0) * Pt, 289.0);
    Pt = mod((34.0 * Pt + 1.0) * Pt, 289.0);

    // Hash gradients
    vec4 hx = Pt / 103.0;
    vec4 hy = mod(floor(hx * 0.01), 289.0);

    // Evaluate gradients
    vec2 C00 = vec2(fract(hx.x), fract(hy.x)) * 2.0 - 1.0;
    vec2 C10 = vec2(fract(hx.y), fract(hy.y)) * 2.0 - 1.0;
    vec2 C01 = vec2(fract(hx.z), fract(hy.z)) * 2.0 - 1.0;
    vec2 C11 = vec2(fract(hx.w), fract(hy.w)) * 2.0 - 1.0;

    // Compute distances
    vec2 d00 = Pf;
    vec2 d10 = Pf - vec2(1.0, 0.0);
    vec2 d01 = Pf - vec2(0.0, 1.0);
    vec2 d11 = Pf - vec2(1.0, 1.0);

    // Compute squared distances
    float v00 = dot(C00, d00);
    float v10 = dot(C10, d10);
    float v01 = dot(C01, d01);
    float v11 = dot(C11, d11);

    // Smoothstep interpolation
    vec2 w = Pf * Pf * (3.0 - 2.0 * Pf);

    float result = mix(
        mix(v00, v10, w.x),
        mix(v01, v11, w.x),
        w.y);

    return vec2(result, result * 1.5); // Return value and derivative
}

float noise(vec2 p) {
    vec2 f = cellular2x2(p);
    return 0.5 + 0.5 * f.x;
}

// Ridged multi-fractal terrain function
float ridged_mf(vec2 p, float ridgeOffset) {
    float sum = 0.0;
    float amp = 0.5;
    float freq = 1.0;

    for(int i = 0; i < 4; i++) {
        float n = noise(p * freq);
        // Transform noise to create ridges
        n = abs(n - ridgeOffset);
        n = pow(n, ridge_sharpness);
        sum += n * amp;

        amp *= 0.5;
        freq *= 2.0;
    }

    return sum;
}

void fragment() {
    // Create scaled and flowing coordinates
    float time = TIME * flow_speed + 50.0;
    vec2 uv = UV * pattern_scale;

    // Create distortion field
    vec2 distort_uv = UV * noise_scale;
    float distortion_x = noise(distort_uv + vec2(time * 0.3, time * 0.2)) * distortion_strength;
    float distortion_y = noise(distort_uv + vec2(-time * 0.4, time * 0.1)) * distortion_strength;

    // Apply distortion to coordinates
    vec2 distorted_uv = uv + vec2(distortion_x, distortion_y);

    // Generate base pattern
    float ridgeOffset = 0.5 + 0.2 * sin(time * 0.2);
    float pattern1 = ridged_mf(distorted_uv + vec2(time * 0.1, time * 0.05), ridgeOffset);
    float pattern2 = ridged_mf(distorted_uv * 0.8 + vec2(-time * 0.15, time * 0.07), 1.0 - ridgeOffset);

    // Combine patterns with time variation
    float combined = mix(pattern1, pattern2, 0.5 + 0.5 * sin(time * 0.1));

    // Create organic flowing field effect
    float field = smoothstep(0.2, 0.8, combined);

    // Add organic flowing details
    float detail = noise(distorted_uv * 3.0 + vec2(time * 0.2, -time * 0.3));
    field = mix(field, detail, 0.3);

    // Create highlights along "ridges"
    float highlight = smoothstep(0.55, 0.6, field);

    // Create lowlights in "valleys"
    float lowlight = smoothstep(0.4, 0.35, field);

    // Mix colors based on field values
    vec3 color = mix(deep_color.rgb, mid_color.rgb, field);
    color = mix(color, highlight_color.rgb, highlight * 0.6);
    color = mix(color, deep_color.rgb * 0.8, lowlight * 0.5);

    // Add subtle variation
    color += (noise(uv * 20.0) - 0.5) * 0.02;

    // Add subtle vignette
    float vignette = 1.0 - length(UV - 0.5) * 0.5;
    color *= vignette;

    ALBEDO = color;
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
}
