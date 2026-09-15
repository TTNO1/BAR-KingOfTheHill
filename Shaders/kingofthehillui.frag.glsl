#version 450 core

// This shader is used by the King of the Hill widget for drawing the progress bars

const int COLOR_INDEX_MASK = 0x0000FFFF;
const int CAPTURE_BAR_FLAG = 0x00800000;
const int DISQUALIFIED_FLAG = 0x00400000;

const int MAX_TEAMS = 32;// Arbitrary array size

const vec4 BACKGROUND_COLOR = vec4(0.1, 0.1, 0.1, 0.35);// Background color of progress bar

const vec4 CAPTURE_BAR_BORDER_COLOR = vec4(0.5, 0.5, 0.5, 1.0);// The color of the outline of the capture bar

const float DISQUALIFIED_OPACITY = 0.4;// The opacity of a bar for a disqualified team

layout (std140, binding = 6) uniform allyTeamColors
{
	vec4[MAX_TEAMS] colors;// Colors of each ally team
};

// The thickness of the progress bar outlines in pixels
uniform int borderThickness;

// The border radius of the progress bars in pixels
uniform int borderRadius; 

// Half the width of every progress bar in pixels (assumed to all be the same)
uniform float progressBarHalfWidth;

// Half the height of every ally team progress bar in pixels (assumed to all be the same)
uniform float allyTeamBarHalfHeight;

// Half the height of the capture progress bar in pixels
uniform float captureBarHalfHeight;

uniform int[MAX_TEAMS + 1] progressThresholds;// The progress threshold in pixel coords with origin at center of bar

uniform int progressBarData;// 16 least significant bits are the index of the color in the colors array above
							//  8 most significant bits are always zero since lua uses floats
							//  8 remaining middle bits define various flags:
							//    MSb
							//    bit 23 = 1 for capture bar, 0 for not capture bar
							//    bit 22 = 1 for disqualified, 0 for not disqualified
							//    LSb

// Pixel coordinates with origin at center of bar
in vec2 pixelCoord;

out vec4 fragColor;

float signedDistanceBox(vec2 point, vec2 box, float radius)
{
    vec2 d = abs(point) - box + radius;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
}

void main()
{
	
	vec4 color;
	int progressThreshold;
	vec4 borderColor;
	float halfHeight;
	
	//if it is the capture bar
	if((progressBarData & CAPTURE_BAR_FLAG) != 0) {
		color = colors[progressBarData & COLOR_INDEX_MASK];
		progressThreshold = progressThresholds[MAX_TEAMS];
		borderColor = CAPTURE_BAR_BORDER_COLOR;
		halfHeight = captureBarHalfHeight;
	} else {
		//get the 16 bits of the color index
		int colorIndex = progressBarData & COLOR_INDEX_MASK;
		color = colors[colorIndex];
		progressThreshold = progressThresholds[colorIndex];
		//if it is disqualified
		if((progressBarData & DISQUALIFIED_FLAG) != 0) {
			color.a = DISQUALIFIED_OPACITY;
		}
		borderColor = color;
		halfHeight = allyTeamBarHalfHeight;
	}
	
	//used to change colors for filled portion and unfilled portion of bar
	float fillFactor = max(min((progressThreshold - pixelCoord.x), 1), 0);
	
	float scaledYCoord = pixelCoord.y/halfHeight + 1;
	//used to create a vertical gradient along the bar
	float verticalGradientFactor = 0.8 + scaledYCoord * scaledYCoord * 0.125;
	
	fragColor = (color * verticalGradientFactor * fillFactor) + ((1 - fillFactor) * BACKGROUND_COLOR);
	
	vec2 box = vec2(progressBarHalfWidth, halfHeight);
	float sd = signedDistanceBox(pixelCoord, box, borderRadius);
	
	float borderFactor = min(max(sd + borderThickness, 0), 1);
	float alphaFactor = max(min(-sd*0.65 + borderThickness, 1), 0);
	
	fragColor = ((1 - borderFactor) * fragColor) + (borderFactor * borderColor);
	fragColor.w = fragColor.w * alphaFactor;
}