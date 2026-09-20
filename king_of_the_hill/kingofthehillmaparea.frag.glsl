#version 450 core

// This shader is used by the King of the Hill widget for drawing the outlines of start boxes and the hill

const int COLOR_INDEX_MASK = 0x0000FFFF;
const int HILL_AREA_FLAG = 0x00800000;

const int MAX_TEAMS = 32;// Arbitrary array size

const vec4 DEFAULT_HILL_COLOR = vec4(0.65, 0.65, 0.65, 1.0);// The hill outline color when no one is king

const float OPACITY = 0.4;// The opacity of the outline

layout (std140, binding = 6) uniform allyTeamColors
{
	vec4[MAX_TEAMS] colors;// Colors of each ally team
};

uniform int mapAreaData;// 16 least significant bits are the index of the color in the colors array above
							//  8 most significant bits are always zero since lua uses floats
							//  8 remaining middle bits define various flags:
							//    MSb = 1 for hill area, 0 for not hill area

out vec4 fragColor;

void main()
{
	int colorIndex = mapAreaData & COLOR_INDEX_MASK;
	vec4 color = colorIndex >= MAX_TEAMS ? DEFAULT_HILL_COLOR : colors[colorIndex];
	bool isHillArea = (mapAreaData & HILL_AREA_FLAG) != 0;
	color.a = isHillArea ? DEFAULT_HILL_COLOR.a : OPACITY;
	fragColor = color;
}