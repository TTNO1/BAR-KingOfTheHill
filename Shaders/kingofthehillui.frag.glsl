#version 450 core

// This shader is used by the King of the Hill widget for drawing the progress bars

const int COLOR_INDEX_MASK = 0x0000FFFF;
const int CAPTURE_BAR_FLAG = 0x00800000;
const int DISQUALIFIED_FLAG = 0x00400000;

const int MAX_TEAMS = 32;// Arbitrary array size

const vec4 BACKGROUND_COLOR = vec4(0.1, 0.1, 0.1, 0.35);// Background color of progress bar

const vec4 CAPTURE_BAR_BORDER_COLOR = vec4(0.5, 0.5, 0.5, 1.0);// The color of the outline of the capture bar

const float DISQUALIFIED_OPACITY = 0.4;// The opacity of a bar for a disqualified team

const float BORDER_THICKNESS = 1;// Thickness of outline in pixels

const float BORDER_RADIUS = 2;// The border radius of the progress bar in pixels

layout (std140, binding = 6) uniform allyTeamColors
{
	vec4[MAX_TEAMS] colors;// Colors of each ally team
};

uniform float[MAX_TEAMS + 1] progress;// The progress level for each ally team and the capture bar

uniform int progressBarData;// 16 least significant bits are the index of the color in the colors array above
							//  8 most significant bits are always zero since lua uses floats
							//  8 remaining middle bits define various flags:
							//    MSb
							//    bit 23 = 1 for capture bar, 0 for not capture bar
							//    bit 22 = 1 for disqualified, 0 for not disqualified
							//    LSb

in vec2 uvCoord;

out vec4 fragColor;

float signedDistanceBox(vec2 point, vec2 box, float radius)
{
    vec2 d = abs(point) - box + radius;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
}

void main()
{
	//get the 16 least significant bits as the color index
	int colorIndex = progressBarData & COLOR_INDEX_MASK;
	vec4 color = colors[colorIndex];
	//most significant bit specifies if it is the capture bar
	bool isCaptureBar = (progressBarData & CAPTURE_BAR_FLAG) != 0;
	//if it is the capture bar, then our progress is at index MAX_TEAMS
	int progressIndex = isCaptureBar ? MAX_TEAMS : colorIndex;
	//second most significant bit specifies if the team is disqualified
	bool isDisqualified = (progressBarData & DISQUALIFIED_FLAG) != 0;
	if(isDisqualified) {
		color.a = DISQUALIFIED_OPACITY;
	}
	//the color of the outline of the bar
	vec4 borderColor = isCaptureBar ? CAPTURE_BAR_BORDER_COLOR : color;
	
	//used to change colors for filled portion and unfilled portion of bar
	float fillFactor = max(min(((progress[progressIndex] * 1.01) - uvCoord.x) * 80, 1), 0);
	//creates a vertical gradient along the bar
	float verticalGradientFactor = 0.8 + uvCoord.y * uvCoord.y * 0.5;
	
	fragColor = (color * fillFactor * verticalGradientFactor) + ((1 - fillFactor) * BACKGROUND_COLOR);
	
	//aspect ratio scaling to create circular corners
	//assumes width >= height
	//TODO consider replacing with uniform aspect ratio
	float duvdyCoarse = dFdyCoarse(uvCoord.y);
	float duvdxCoarse = dFdxCoarse(uvCoord.x);
	vec2 scaledBox = vec2(0.5 / duvdxCoarse, 0.5 / duvdyCoarse);
	vec2 scaledPos = vec2((uvCoord.x - 0.5) / duvdxCoarse, (uvCoord.y - 0.5) / duvdyCoarse);
	
	float sd = signedDistanceBox(scaledPos, scaledBox, BORDER_RADIUS);
	float borderFactor = min(max((sd + BORDER_THICKNESS) * 100, 0), 1);
	float aplhaFactor = max(min(-sd * 10, 1), 0);
	
	fragColor = ((1 - borderFactor) * fragColor) + (borderFactor * borderColor);
	fragColor.w = fragColor.w * aplhaFactor;
}