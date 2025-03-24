shader_type spatial;
render_mode unshaded;

// Color options
uniform vec4 bg_color_1 : source_color = vec4(0.05, 0.12, 0.22, 1.0);
uniform vec4 bg_color_2 : source_color = vec4(0.12, 0.2, 0.35, 1.0);
uniform vec4 grid_color : source_color = vec4(0.15, 0.4, 0.7, 1.0);
uniform vec4 highlight_color : source_color = vec4(0.4, 0.8, 1.0, 1.0);

// Pattern controls
uniform float time_scale : hint_range(0.001, 0.5) = 0.1;
uniform float grid_scale : hint_range(1.0, 100.0) = 40.0;
uniform float grid_intensity : hint_range(0.0, 1.0) = 0.2;
uniform float flow_speed : hint_range(0.0, 1.0) = 0.2;
uniform float wave_height : hint_range(0.0, 5.0) = 1.0;
uniform float wave_frequency : hint_range(0.0, 10.0) = 2.0;

// Noise function
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    
    // Smoothing
    vec2 u = f * f * (3.0 - 2.0 * f);
    
    // Four corners
    float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453123);
    float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453123);
    float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453123);
    float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453123);
    
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// FBM (Fractal Brownian Motion)
float fbm(vec2 p) {
    float sum = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    
    for(int i = 0; i < 6; i++) {
        sum += amp * noise(p * freq);
        amp *= 0.5;
        freq *= 2.0;
    }
    
    return sum;
}

// Draw a grid line
float grid_line(float position, float thickness) {
    float half_thickness = thickness * 0.5;
    return smoothstep(half_thickness, 0.0, abs(position - round(position)));
}

void fragment() {
    float time = TIME * time_scale;
    vec2 uv = UV;
    
    // Create a flowing distortion for an organic feel
    float flow_offset = fbm(uv * 2.0 + vec2(time * flow_speed, time * flow_speed * 0.7)) * 0.15;
    vec2 distorted_uv = uv + vec2(flow_offset * sin(time), flow_offset * cos(time * 0.7));
    
    // Create a moving wave pattern
    float wave = sin(distorted_uv.x * wave_frequency + time) * sin(distorted_uv.y * wave_frequency + time * 0.7) * wave_height;
    float wave_factor = 0.5 + 0.5 * sin(wave);
    
    // Create a gradient background
    float gradient = length(uv - 0.5) * 1.2;
    vec3 color = mix(bg_color_1.rgb, bg_color_2.rgb, clamp(gradient + wave_factor * 0.2, 0.0, 1.0));
    
    // Optional very subtle grid (can be turned off by setting grid_intensity to 0)
    if (grid_intensity > 0.0) {
        float grid_x = grid_line(distorted_uv.x * grid_scale, 0.01 + 0.005 * sin(time + uv.y * 10.0));
        float grid_y = grid_line(distorted_uv.y * grid_scale, 0.01 + 0.005 * sin(time + uv.x * 10.0));
        float grid = (grid_x + grid_y) * grid_intensity;
        
        // Apply grid with low intensity
        color = mix(color, grid_color.rgb, grid * 0.7);
        
        // Add extremely subtle glow at intersections
        float grid_points = grid_x * grid_y * 2.0;
        color = mix(color, highlight_color.rgb, grid_points * grid_intensity * 0.5);
    }
    
    // Add subtle vignette
    float vignette = 1.0 - length(UV - 0.5) * 0.8;
    color *= vignette;
    
    // Add subtle pulsing
    color *= 0.9 + 0.1 * sin(time * 0.5);
    
    ALBEDO = color;
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
}
