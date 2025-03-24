shader_type spatial;
render_mode unshaded;

// Color options
uniform vec4 bg_color_1 : source_color = vec4(0.05, 0.07, 0.15, 1.0);
uniform vec4 bg_color_2 : source_color = vec4(0.1, 0.15, 0.3, 1.0);
uniform vec4 grid_color : source_color = vec4(0.1, 0.4, 0.7, 1.0);
uniform vec4 highlight_color : source_color = vec4(0.4, 0.8, 1.0, 1.0);
uniform vec4 particle_color : source_color = vec4(0.9, 0.9, 1.0, 1.0);
uniform vec4 accent_color : source_color = vec4(0.2, 0.8, 0.6, 1.0);

// Pattern controls
uniform float time_scale : hint_range(0.001, 0.5) = 0.1;
uniform float grid_scale : hint_range(1.0, 100.0) = 40.0;
uniform float grid_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float glow_intensity : hint_range(0.0, 3.0) = 1.2;
uniform float flow_speed : hint_range(0.0, 1.0) = 0.2;
uniform float wave_height : hint_range(0.0, 5.0) = 1.0;
uniform float wave_frequency : hint_range(0.0, 10.0) = 2.0;
uniform bool show_particles = true;
uniform float particle_density : hint_range(0.0, 1.0) = 0.4;
uniform float particle_speed : hint_range(0.0, 2.0) = 0.5;
uniform float tech_elements_density : hint_range(0.0, 1.0) = 0.3;

// Hash functions
float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.103, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Noise function
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    
    // Smoothing
    vec2 u = f * f * (3.0 - 2.0 * f);
    
    // Four corners
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    
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

// Draw a glowing grid line
float grid_line(float position, float thickness) {
    float half_thickness = thickness * 0.5;
    return smoothstep(half_thickness, 0.0, abs(position - round(position)));
}

// Draw a particle
float draw_particle(vec2 uv, vec2 position, float size) {
    float d = length(uv - position);
    return smoothstep(size, size * 0.5, d);
}

// Generates code-like particles
float code_particles(vec2 uv, float time) {
    float particles = 0.0;
    
    // Grid-aligned particles
    for (int i = 0; i < 10; i++) {
        float random_seed = float(i) * 456.789;
        vec2 grid_pos = vec2(
            floor(hash21(vec2(random_seed, 0.42)) * 10.0),
            floor(hash21(vec2(random_seed, 0.91)) * 10.0)
        );
        
        // Moving along grid lines
        float particle_time = fract(time * 0.2 + hash21(grid_pos) * 10.0);
        
        // Particle position animated along grid
        vec2 pos = (grid_pos + vec2(0.5)) / 10.0;
        pos.y = mix(pos.y, fract(pos.y + time * particle_speed * 0.1), hash21(vec2(grid_pos.x, random_seed)));
        
        // Only show some particles
        if (hash21(grid_pos * 0.76) < particle_density) {
            float size = 0.004 + 0.003 * hash21(grid_pos * 1.32);
            particles += draw_particle(uv, pos, size) * (0.6 + 0.4 * sin(time * 3.0 + hash21(grid_pos) * 10.0));
        }
    }
    
    // Add some random-positioned particles
    for (int i = 0; i < 15; i++) {
        float random_seed = float(i) * 123.456;
        
        // Random position with time-based movement
        vec2 pos = vec2(
            fract(hash21(vec2(random_seed, 0.123)) + time * particle_speed * 0.05 * hash21(vec2(random_seed, 0.987))),
            fract(hash21(vec2(random_seed, 0.456)) - time * particle_speed * 0.1 * hash21(vec2(random_seed, 0.321)))
        );
        
        // Only show some particles
        if (hash21(vec2(random_seed, 0.789)) < particle_density * 0.5) {
            float size = 0.002 + 0.002 * hash21(vec2(random_seed, 0.654));
            particles += draw_particle(uv, pos, size) * (0.5 + 0.5 * sin(time * 2.0 + hash21(vec2(random_seed)) * 6.28));
        }
    }
    
    return clamp(particles, 0.0, 1.0);
}

// Draw a circuit pattern
float circuit_pattern(vec2 uv, float time) {
    // Scale the UV coordinates to create a grid
    vec2 grid_uv = floor(uv * grid_scale * 0.4);
    float random = hash21(grid_uv);
    
    // Only draw in some cells
    if (random < tech_elements_density * 0.5) {
        vec2 cell_uv = fract(uv * grid_scale * 0.4) * 2.0 - 1.0;
        
        // Determine what type of circuit element to draw
        float element_type = floor(random * 6.0);
        
        // Horizontal line
        if (element_type < 1.0) {
            return smoothstep(0.1, 0.05, abs(cell_uv.y)) * step(abs(cell_uv.x), 0.9);
        }
        // Vertical line
        else if (element_type < 2.0) {
            return smoothstep(0.1, 0.05, abs(cell_uv.x)) * step(abs(cell_uv.y), 0.9);
        }
        // Corner (L shape)
        else if (element_type < 3.0) {
            float h_line = smoothstep(0.1, 0.05, abs(cell_uv.y)) * step(cell_uv.x, 0.0);
            float v_line = smoothstep(0.1, 0.05, abs(cell_uv.x)) * step(cell_uv.y, 0.0);
            return max(h_line, v_line);
        }
        // T junction
        else if (element_type < 4.0) {
            float h_line = smoothstep(0.1, 0.05, abs(cell_uv.y)) * step(abs(cell_uv.x), 0.9);
            float v_line = smoothstep(0.1, 0.05, abs(cell_uv.x)) * step(cell_uv.y, 0.0);
            return max(h_line, v_line);
        }
        // Circle/node
        else if (element_type < 5.0) {
            float d = length(cell_uv);
            return smoothstep(0.3, 0.25, d);
        }
        // Cross
        else {
            float h_line = smoothstep(0.1, 0.05, abs(cell_uv.y));
            float v_line = smoothstep(0.1, 0.05, abs(cell_uv.x));
            return max(h_line, v_line);
        }
    }
    
    return 0.0;
}

// Code brackets and syntax elements
float code_syntax(vec2 uv, float time) {
    vec2 grid_uv = floor(uv * grid_scale * 0.25);
    float random = hash21(grid_uv);
    
    if (random < tech_elements_density * 0.4) {
        vec2 cell_uv = fract(uv * grid_scale * 0.25) * 2.0 - 1.0;
        
        // Animation factor
        float time_factor = fract(time * 0.1 + random);
        float fade = smoothstep(0.0, 0.2, time_factor) * smoothstep(1.0, 0.8, time_factor);
        
        // Element type
        float element_type = floor(random * 10.0);
        
        // Brackets: { }
        if (element_type < 2.0) {
            float left = smoothstep(0.15, 0.1, abs(cell_uv.x + 0.5)) * smoothstep(0.7, 0.65, abs(cell_uv.y));
            float right = smoothstep(0.15, 0.1, abs(cell_uv.x - 0.5)) * smoothstep(0.7, 0.65, abs(cell_uv.y));
            float top = smoothstep(0.15, 0.1, abs(cell_uv.y - 0.7)) * 
                     (step(-0.7, cell_uv.x) * step(cell_uv.x, -0.3) + step(0.3, cell_uv.x) * step(cell_uv.x, 0.7));
            float bottom = smoothstep(0.15, 0.1, abs(cell_uv.y + 0.7)) * 
                     (step(-0.7, cell_uv.x) * step(cell_uv.x, -0.3) + step(0.3, cell_uv.x) * step(cell_uv.x, 0.7));
            return (left + right + top + bottom) * fade * 0.8;
        }
        // Parentheses: ( )
        else if (element_type < 4.0) {
            float d_left = length(vec2(cell_uv.x + 0.5, cell_uv.y)) - 0.7;
            float d_right = length(vec2(cell_uv.x - 0.5, cell_uv.y)) - 0.7;
            float left = smoothstep(0.15, 0.1, abs(d_left)) * step(cell_uv.x, -0.3);
            float right = smoothstep(0.15, 0.1, abs(d_right)) * step(0.3, cell_uv.x);
            return (left + right) * fade * 0.8;
        }
        // Square brackets: [ ]
        else if (element_type < 6.0) {
            float left = smoothstep(0.15, 0.1, abs(cell_uv.x + 0.6)) * step(abs(cell_uv.y), 0.7);
            float right = smoothstep(0.15, 0.1, abs(cell_uv.x - 0.6)) * step(abs(cell_uv.y), 0.7);
            float top = smoothstep(0.15, 0.1, abs(cell_uv.y - 0.7)) * 
                     (step(-0.7, cell_uv.x) * step(cell_uv.x, -0.5) + step(0.5, cell_uv.x) * step(cell_uv.x, 0.7));
            float bottom = smoothstep(0.15, 0.1, abs(cell_uv.y + 0.7)) * 
                     (step(-0.7, cell_uv.x) * step(cell_uv.x, -0.5) + step(0.5, cell_uv.x) * step(cell_uv.x, 0.7));
            return (left + right + top + bottom) * fade * 0.8;
        }
        // Angle brackets: < >
        else if (element_type < 8.0) {
            float left = smoothstep(0.15, 0.1, abs(abs(cell_uv.y) + cell_uv.x - 0.6)) * step(cell_uv.x, 0.0);
            float right = smoothstep(0.15, 0.1, abs(abs(cell_uv.y) - cell_uv.x + 0.6)) * step(0.0, cell_uv.x);
            return (left + right) * fade * 0.8;
        }
        // Equal sign: =
        else if (element_type < 9.0) {
            float top = smoothstep(0.15, 0.1, abs(cell_uv.y - 0.2)) * step(abs(cell_uv.x), 0.5);
            float bottom = smoothstep(0.15, 0.1, abs(cell_uv.y + 0.2)) * step(abs(cell_uv.x), 0.5);
            return (top + bottom) * fade * 0.8;
        }
        // Arrow: ->
        else {
            float line = smoothstep(0.15, 0.1, abs(cell_uv.y)) * step(-0.5, cell_uv.x) * step(cell_uv.x, 0.3);
            float arrow1 = smoothstep(0.15, 0.1, abs(abs(cell_uv.y) + cell_uv.x - 0.7)) * step(0.3, cell_uv.x) * step(cell_uv.x, 0.7);
            float arrow2 = smoothstep(0.15, 0.1, abs(abs(cell_uv.y) - cell_uv.x + 0.7)) * step(0.3, cell_uv.x) * step(cell_uv.x, 0.7);
            return (line + arrow1 + arrow2) * fade * 0.8;
        }
    }
    
    return 0.0;
}

// Data flow lines
float data_flow(vec2 uv, float time) {
    float result = 0.0;
    
    // Create several animated flow lines
    for (int i = 0; i < 8; i++) {
        float random_seed = float(i) * 67.89;
        float flow_x = hash21(vec2(random_seed, 0.42));
        float flow_y = hash21(vec2(random_seed, 0.91));
        
        // Only create some flow lines
        if (hash21(vec2(random_seed, 0.13)) < tech_elements_density * 0.7) {
            // Generate a position for the flow line
            float grid_x = floor(flow_x * float(grid_scale));
            float grid_y = floor(flow_y * float(grid_scale));
            
            // Direction of flow (horizontal or vertical)
            bool horizontal = hash21(vec2(grid_x, grid_y)) > 0.5;
            
            // Flow pulse position
            float pulse_pos = fract(time * particle_speed * (0.1 + 0.1 * hash21(vec2(random_seed, 0.67))));
            
            if (horizontal) {
                // Check if we're on this grid line
                float line_pos = (grid_y + 0.5) / grid_scale;
                if (abs(uv.y - line_pos) < 0.002) {
                    // Draw flowing pulse
                    float pulse_x = pulse_pos;
                    float pulse_width = 0.03 + 0.02 * hash21(vec2(grid_y, random_seed));
                    result += smoothstep(pulse_width, 0.0, abs(uv.x - pulse_x)) * 0.8;
                }
            } else {
                // Check if we're on this grid line
                float line_pos = (grid_x + 0.5) / grid_scale;
                if (abs(uv.x - line_pos) < 0.002) {
                    // Draw flowing pulse
                    float pulse_y = pulse_pos;
                    float pulse_width = 0.03 + 0.02 * hash21(vec2(grid_x, random_seed));
                    result += smoothstep(pulse_width, 0.0, abs(uv.y - pulse_y)) * 0.8;
                }
            }
        }
    }
    
    return clamp(result, 0.0, 1.0);
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
    vec3 bg = mix(bg_color_1.rgb, bg_color_2.rgb, clamp(gradient + wave_factor * 0.2, 0.0, 1.0));
    
    // Create grid lines
    float grid_x = grid_line(distorted_uv.x * grid_scale, 0.02 + 0.01 * sin(time + uv.y * 10.0));
    float grid_y = grid_line(distorted_uv.y * grid_scale, 0.02 + 0.01 * sin(time + uv.x * 10.0));
    float grid = (grid_x + grid_y) * grid_intensity;
    
    // Create a glow effect around grid intersections
    float grid_points = grid_x * grid_y * 4.0;
    float glow = smoothstep(0.3, 1.0, grid_points) * glow_intensity * (0.5 + 0.5 * sin(time * 2.0));
    
    // Tech elements
    float particles = 0.0;
    float tech_elements = 0.0;
    
    if (show_particles) {
        // Data particles moving along the grid
        particles = code_particles(uv, time) * 0.8;
        
        // Circuit patterns
        tech_elements += circuit_pattern(distorted_uv, time) * 0.7;
        
        // Code syntax elements
        tech_elements += code_syntax(distorted_uv, time) * 0.6;
        
        // Data flow animations
        tech_elements += data_flow(uv, time) * 0.9;
    }
    
    // Combine all effects
    vec3 color = bg;
    color = mix(color, grid_color.rgb, grid);
    color = mix(color, highlight_color.rgb, glow);
    color = mix(color, particle_color.rgb, particles);
    color = mix(color, accent_color.rgb, tech_elements);
    
    // Add subtle vignette
    float vignette = 1.0 - length(UV - 0.5) * 0.8;
    color *= vignette;
    
    // Add subtle pulsing
    color *= 0.9 + 0.1 * sin(time * 0.5);
    
    ALBEDO = color;
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
}
