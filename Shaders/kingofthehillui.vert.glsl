#version 450 core

// This shader is used by the King of the Hill widget for drawing the progress bars and the boundary lines.

layout (location = 0) in vec2 vertex_position;

layout (location = 1) in vec2 uv_coord;

out vec2 uvCoord;

void main()
{
	gl_Position = vec4(vertex_position.xy, 0.0, 1.0);
	uvCoord = uv_coord;
}