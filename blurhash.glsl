#define pi 3.1415926535897932384626433832795
uniform int size_x;
uniform int size_y;
uniform int screen_width;
uniform int screen_height;
uniform vec3 colors[81];
	
float to_srgb(float value)
{
	float v = max(0.0, min(1.0, value));
	if (v <= 0.0031308) {
        return v * 12.92;
	}
	return 1.055 * pow(v, 1.0 / 2.4) - 0.055;
}

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords)
{
	vec4 pixel = vec4(0, 0, 0, 1);
	
	for (int j = 0; j < size_y; j++) {
        for (int i = 0; i < size_x; i++) {
            float basis = cos(pi * screen_coords[0] * i / screen_width) * cos(pi * screen_coords[1] * j / screen_height);
            vec3 color = colors[i + j * size_x];
            pixel[0] += color[0] * basis;
            pixel[1] += color[1] * basis;
            pixel[2] += color[2] * basis;
        }
	}
	pixel[0] = to_srgb(pixel[0]);
	pixel[1] = to_srgb(pixel[1]);
	pixel[2] = to_srgb(pixel[2]);

	return pixel * color;
}
