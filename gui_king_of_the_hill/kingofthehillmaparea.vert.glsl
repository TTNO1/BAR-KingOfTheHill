#version 450 core

// This shader is used by the King of the Hill widget for drawing the start box and hill outlines.

//##UBO##

layout (location = 0) in vec3 vertex_position;

void main()
{
	gl_Position = cameraViewProj * vec4(vertex_position.xyz, 1.0);
}