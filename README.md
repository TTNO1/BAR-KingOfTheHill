<!--# King of the Hill
This is a widget for [Beyond All Reason](https://github.com/beyond-all-reason/Beyond-All-Reason) that adds a king of the hill game mode.-->

# King of the Hill (Beta)

This widget adds a 'king of the hill' game mode to BAR.<br>
This widget must be installed by every player to work.

In this game mode, a team wins by spending a certain amount of time as the king. A team becomes the king by being the only team with commander(s) in the hill for a certain amount of time. The hill is a configurable region on the map.

## How to Use

### Installation
To install the widget, copy [kingofthehill.lua](https://github.com/TTNO1/BAR-KingOfTheHill/blob/master/Widgets/kingofthehill.lua) ([raw](https://github.com/TTNO1/BAR-KingOfTheHill/raw/refs/heads/master/Widgets/kingofthehill.lua)) into your `LuaUI/Widgets` folder and copy all of the [shader files](https://github.com/TTNO1/BAR-KingOfTheHill/tree/master/Shaders) into your `LuaUI/Shaders` folder.

The widget must be installed by every player in the match. If one player does not have it, they will not be a part of the KOTH game.

### Mod Options

The widget has various configurable settings that define the rules of the game. Because the widget is installed by every player, the settings are not set in the Lua file but through the *tweakdefs* mod option.

To enable the widget in a game, the following lines must be added to any of the *tweakdefs* mod options (before they are base64 encoded).
```Lua
--###KOTH_MODOPTIONS###
--###KOTH_MODOPTIONS###
```

In between those lines, various settings can be configured as follows.
```Lua
--###KOTH_MODOPTIONS###
KOTHModoptions = {
	hillAreaArgs = {type = "circle", x = 0.5, z = 0.5, radius = 0.25},
	startBoxBuildRule = 1,
	hillBuildRule = 2,
	winKingTime = 360000,
	captureDelay = 15000,
	kingKeepsHill = true,
	noDamageInBoxes = true,
	explodeHillUnits = true,
	captureQualifiedUnitNames = {"armcom", "corcomlvl2", --[[etc.]]}
}
--###KOTH_MODOPTIONS###
```

Any mod options that are not included will resort to their default settings.

<details>
<summary>Click here for a full explanation of the mod options.</summary>

### `hillAreaArgs`:table
This is a table that defines the hill area on the map. It may be a rectangular region or a circular region. The coordinates are given on a scale from 0 to 1 as proportions of the map's width/height.<br>
**Circle:**<br>
`{type = "circle", x = 0.5, z = 0.5, radius = 0.25}`<br>
**Rectangle:**<br>
`{type = "rect", left = 0.375, right = 0.625, top = 0.375, bottom = 0.625}`

*Default:* `{type = "circle", x = 0.5, z = 0.5, radius = 0.25}`

### `startBoxBuildRule`:number
This defines where players are allowed to build buildings on the map.<br>
- `1` = players can only build buildings in their own start box
- `2` = players can build buildings anywhere except in other teams' start boxes
- `3` = players can build buildings anywhere

This option does not affect the `hillBuildRule` option.

*Default:* `1`

### `hillBuildRule`:number
This defines who is allowed to build buildings inside of the hill.<br>
- `1` = No one can ever build inside the hill
- `2` = Only the current king can build inside the hill
- `3` = Everyone can always build in the hill

This option is not affected by the `startBoxBuildRule` option.

*Default:* `2`

### `winKingTime`:number
This is the total number of milliseconds for which a team must have been king to win the game.

*Default:* `360000` (6 minutes)

### `captureDelay`:number
This is the total number of milliseconds for which a team must be the only team with capture-qualified units in the hill to capture the hill and become king. This is also the amount of time that it takes for the current king to loose the hill if they are no longer in the hill.

*Default:* `15000` (15 seconds)

### `kingKeepsHill`:boolean
If `true`, the king will remain the king until he has no capture-qualified units in the hill, at which point the capture timer will start counting down from `captureDelay` before the king looses the hill.<br>
If `false`, the king will remain the king until he is not the only team with capture-qualified units in the hill, at which point the capture timer will start counting down from `captureDelay` before the king looses the hill.

*Default:* `true`

### `noDamageInBoxes`:boolean
If `true`, your units will attempt to be immune to damage when they are inside of your start box. Because this is only a widget, this is implemented by preventing other teams from attacking units inside your start box. This is simple when a player orders a unit to attack inside your start box. However, when a unit roams into your start box, that unit will be forced to hold fire and there may be a minor delay between that unit attacking your start box and the hold fire command taking effect.

*Default:* `true`

### `explodeHillUnits`:boolean
If `true`, any buildings that were built inside the hill will be self-destructed whenever the king looses the hill.<br>
This widget will block you from canceling the self-destruct command.

*Default:* `true`

### `captureQualifiedUnitNames`:array
This is an array of all of the unit names that will be considered capture-qualified units. A capture-qualified unit is any unit that is capable of capturing the hill if its team is the only team with capture-qualified units in the hill.<br>
A list of unit names can be found [here](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/master/language/en/units.json).

*Default:* all commander unit types

</details><br>

**To easily configure the mod options** to your liking, you can use this webpage:
[https://ttno1.github.io/BAR-KingOfTheHill](https://ttno1.github.io/BAR-KingOfTheHill).<br>
It will allow you to graphically configure the hill region and easily select all of the other mod options. The output can then be copied and pasted as Base64 encoded Lua into the *tweakdefs* modoption or as Lua code onto your existing *tweakdefs* code.

Additionally, it is highly recommended to enable **respawning commanders** when playing King of the Hill.

### How to Play

When you join a game with King of the Hill enabled, you will see a GUI box in the bottom right of the screen containing a list of players. A player's name will be grayed out if that player is not part of the king of the hill session. When they join the session, their name will be colored in and a chat message will indicate that they have joined.<br>
Below the list of players, several KOTH mod options are listed to inform you of the current game configuration.<br>
This box will automatically hide itself once the game starts. You can show and hide it at any time by clicking on any of the King of the Hill GUI boxes.

Below that is a box with several progress bars. Each team has a progress bar that indicates how much time they must spend as the king before they win.<br>
At the bottom, the larger progress bar indicates which team is capturing the hill and how much time is left before they capture it.



## Limitations
- Every player must have the widget installed.
- Reloading the widget is not supported.
- The UI will lag behind the game by as much as the most lagging player is lagging.
- Currently, the UI only supports displaying up to 32 players in a game.
- Because this is only a widget, it cannot prevent against all kinds of cheating.