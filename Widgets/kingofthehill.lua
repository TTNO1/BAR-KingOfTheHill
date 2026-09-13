-----------------------------------------------------------------------------------------------
--
-- Copyright 2024
-- 
-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the “Software”), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
-- the Software, and to permit persons to whom the Software is furnished to do so,
-- subject to the following conditions:
-- 
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
-- 
-- THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
-- FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
-- COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
-- IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
-- CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--
-----------------------------------------------------------------------------------------------
--
-- Name: King of the Hill
-- Description: This widget adds a peer-to-peer king of the hill game mode
-- Author: Saul Goodman
--
-----------------------------------------------------------------------------------------------
--
-- Documentation
--
-- This widget must be installed on every participating player in the game for it to work.
-- It uses unsynced, client-to-client communication to keep track of the KOTH game state.
-- 
-- In the KOTH game mode, an ally team wins by spending a certain amount of time as "king".
-- The hill is a configurable circular or square cylinder on the map. An ally team becomes
-- the king by being the only team with "capture-qualified units" in the hill for a
-- configurable amount of time. Capture-qualified units are a set of units that are
-- capable of capturing the hill.
--
-- The main game logic takes place in the widget:GameFrame method. Every couple of frames,
-- it checks where all of the user's capture-qualified units are and determines if any of
-- them are in the hill. It then sends this "update" to all of the other players. When an
-- update has been received from every player for a given frame, the state of the KOTH game
-- can be processed for that frame. Thus, the state of the KOTH game, and the KOTH UI,
-- will lag behind the BAR game state by an amount determined by the maximum lag of any
-- player in the game.
--
-- This widget also sends 'UIMsgPacket's, which are updates to the KOTH game state that are
-- sent infrequently. These packets have an associated frame number on which they are to take
-- effect.
--
-- An "active player" is any player that is currently able to send valid KOTH updates.
-- Because an update must be sent for every interval from the beginning of the game, any
-- disruption to these updates will cause a player to be deactivated. A deactivated player
-- cannot be reactivated. Moreover, if an ally team dies, its players are deactivated.
--
-- The time that each ally team has been king is tracked in a table containing the number
-- of frames for which they have been king. The time for which the current king has been king
-- is not included in this table. Instead, the frame at which the current king became king is
-- stored and the table is updated when the king changes.
-- Moreover, for the team currently capturing the hill, the frame at which the capturing will
-- be complete is stored along with the direction of the capture (whether they are capturing
-- or losing the hill).
--
-- This widget also adds a box to the stack of boxes in the bottom-right corner of the screen.
-- The box contains a progress bar for each ally team indicating how close they are to winning.
-- This widget also draws outlines on the map around each team's starting box and the hill region.
--
-- The outlines on the map are drawn using a set of vertices on each outline and rendered
-- as GL.LINE_LOOP. The progress bars are each rectangles with a custom fragment shader
-- that colors the filled portion of the progress bar.
--
-- Due to its unsynced nature, this widget is not capable of preventing all cheating. Therefore,
-- all the players participating in a KOTH match must be acting in good faith.
--
-----------------------------------------------------------------------------------------------

function widget:GetInfo()
	return {
		name = "King of the Hill",
		desc = "Adds P2P King of the Hill game mode.",
		author = "Saul Goodman",
		date = "2025",
		license = "MIT",
		layer = -10,--Must come before gui_advplayerslist
		enabled = true
	};
end

-- #region Global Constants and Functions

local Spring = Spring
local Game = Game
local mapSizeX = Game.mapSizeX
local mapSizeZ = Game.mapSizeZ
local squareSize = Game.squareSize
local UnitDefs = UnitDefs
local UnitDefNames = UnitDefNames
local fps = Game.gameSpeed
local vsx, vsy--view size x and y
local gl = gl
local GL = GL

local tonumber = tonumber
local math = math
table.unpack = table.unpack or unpack
local table = table
local string = string
local substring = string.sub
local findString = string.find
local splitString = string.split
local floor = math.floor
local ceil = math.ceil
local min = math.min
local max = math.max
local abs = math.abs
local loadstring = loadstring or load

local CMD_MOVE = 10
local CMD_PATROL = 15
local CMD_FIGHT = 16
local CMD_ATTACK = 20
local CMD_FIRE_STATE = 45
local CMD_SELF_DESTRUCT = 65
local CMD_SET_TARGET = 34923

local FIRE_STATE_HOLD_FIRE = 0

local LINE_TYPE_SYSTEM = 5

-- #endregion

-- #region Configuration Constants

--Defines the version of this widget. If two players are using different versions, they will not be able to play with each other.
local kothWidgetVersion = 1

-- the widget name used for logging
local logWidgetName = "KOTH"

-- the comment line in the tweak defs that surrounds the KOTH mod options table
local tweakDefsModOptionsDelimiter = "--###KOTH_MODOPTIONS###"

-- the default list of capture-qualified units
local defaultCaptureQualifiedUnitNames = {
	"armcom", "armcomboss", "armcomlvl2", "armcomlvl3", "armcomlvl4", "armcomlvl5",
	"armcomlvl6", "armcomlvl7", "armcomlvl8", "armcomlvl9", "armcomlvl10", "corcom", "corcomboss", "corcomlvl2",
	"corcomlvl3", "corcomlvl4", "corcomlvl5", "corcomlvl6", "corcomlvl7", "corcomlvl8", "corcomlvl9", "corcomlvl10",
	"legcom", "legcomecon", "legcomdef", "legcomoff", "legcomt2def", "legcomt2off", "legcomt2com", "legcomlvl2",
	"legcomlvl3", "legcomlvl4", "legcomlvl5", "legcomlvl6", "legcomlvl7", "legcomlvl8", "legcomlvl9", "legcomlvl10"
}

local defaultModOptions = {
	captureQualifiedUnitNames = defaultCaptureQualifiedUnitNames,
	hillAreaArgs = {type = "circle", x = 0.5, z = 0.5, radius = 0.25},
	buildOutsideBoxes = false,
	hillBuildRule = 2,
	winKingTime = 360000,
	captureDelay = 15000,
	kingKeepsHill = true,
	noDamageInBoxes = true,
	explodeHillUnits = true
}

--Defines the maximum number of vertices that will be used to draw a map area outline
local mapAreaMaxVertices = 190

--Defines the desired spacing (in world coords) between each map area vertex provided the total number does not exceed the maximum above
local mapAreaPreferredSpacing = 15

--Defines the width of the map area outlines
local mapAreaLineWidth = 1.5

--Defines how much to add the the y coordinate of each vertex of the map area outlines
local mapAreaLineVertexVerticalShift = 5

--Defines the name of the player list widget for ui box positioning
local playerListWidgetName = "advplayerlist_api"

--Defines the order in which to look for the widget below ours. The first widget that is found is used as
--the one below ours for positioning the ui box
local belowWidgetsInOrder = {"playertv", "displayinfo", "unittotals", "music", playerListWidgetName}

--Defines the default width of the UI box if there are no boxes below it to go off of
local defaultUIBoxWidth = 340

--Defines the top and bottom padding on the ui box in pixels
local uiBoxVerticalPadding = 10

--Defines the horizontal padding in the ui box relative to box width
local uiBoxHorizontalPadding = 0.05

--Defines the width of a team progress bar relative to the ui box width
local progressBarWidth = 0.7

--Defines the height of a team progress bar in pixels
local progressBarHeight = 10

--Defines the vertical space between each team progress bar in pixels
local progressBarVerticalSpacing = 6

--Defines the height of the capture progress bar in pixels
local captureProgressBarHeight = 15

--Defines the margin above the capture bar in pixels
local captureProgressBarTopMargin = 15

--Defines the spacing in between the timers and progress bars relative to box width
local timerLeftMargin = 0.05

--Defines the vertical spacing of the items in the additional info box in pixels
local addInfoVerticalSpacing = {
	teamMargin = 7,--space below team name
	modOptionMargin = 4,--space below mod option lines
	allyTeamMargin = 15,--space below an ally team group
	sectionMargin = 25,--space below a section (team list section)
}

--Default font size of UI elements
local fontSizes = {
	default = 13,
	timers = 13,
	addInfoTeamNames = 16,
	addInfoModOptionNames = 13,
	addInfoModOptionValues = 14,
}

local fontColors = {
	white = {1, 1, 1, 1},
	fadedGray = {0.7, 0.7, 0.7, 0.5},
	lessFadedGray = {0.75, 0.75, 0.75, 0.7},
	green = {0.12, 0.85, 0.12, 1},
	yellow = {1, 0.97, 0, 1},
	red = {0.92, 0.05, 0.05, 1},
}

--Defines the path to the regular font file
local exo2FontPath = "fonts/Exo2-Regular.otf"

--Defines the path to the semi-bold font file
local exo2SemiBoldFontPath = "fonts/Exo2-SemiBold.otf"

--Progress bar shader file paths
local progressBarVertexShaderPath = "LuaUI/Shaders/kingofthehillui.vert.glsl"
local progressBarFragmentShaderPath = "LuaUI/Shaders/kingofthehillui.frag.glsl"

--Map area shader file paths
local mapAreaVertexShaderPath = "LuaUI/Shaders/kingofthehillmaparea.vert.glsl"
local mapAreaFragmentShaderPath = "LuaUI/Shaders/kingofthehillmaparea.frag.glsl"

--The size of the arrays in the fragment shaders
local fragmentShaderMaxTeams = 32

--Specifies the interval at which the game state and UI are updated (i.e. updated every x frames)
local framesPerUpdate = 5

--The minimum number of frames between UnitDamaged callin will run again (used to reduce number of checks)
local minFramesBetweenDamageCheck = 20

-- The minimum amount of frames to wait before deactivating a player after they are removed (see PlayerRemoved callin)
local minimumWaitFramesAfterDisconnect = fps * 5

-- The maximum amount of frames to wait before deactivating a player after they are removed (see PlayerRemoved callin)
local maximumWaitFramesAfterDisconnect = fps * 20

-- Used to update the position of the UI box multiple times after the screen is resized
-- since the ordering of the size updates from the lower widgets is unknown to me.
-- This represents the number of frames after the screen is resized for which we will
-- update the widget box size to match those below it
local maxScreenResizeCountdown = fps*2

-- Before the game has started, a VersionInitUIPacket will be sent on this interval in seconds
local sendInitPacketIntervalSecs = 1.5

--The character that is sent to and received from other players to indicate that the sending
--player has a capture qualified unit in the hill
local inHillChar = "$"

--The character that is sent to and received from other players to indicate that the sending
--player does not have a capture qualified unit in the hill
local notInHillChar = "^"

--If a player falls this many frames behind, remove them from the set of active players
--local maxLagFramesForActivePlayer = 20 * fps

-- #endregion

-- /////////////////////////////
-- #region     Utils
-- /////////////////////////////

-- ---- Util Classes ----
-- ----------------------

--A Set class based on the Java API Set
local Set = {
	mt = {},
	type = "set",
	iterator = function (invariantState, controlVariable)
		local element = next(invariantState, controlVariable)
		return element
	end
}
Set.mt.__index = Set
function Set.new()
	local set = {size = 0, elements = {}}
	setmetatable(set, Set.mt)
	return set
end
function Set.varIter(...)
	local args
	if type((...)) == "table" then
		args = ...
		if args.type == "set" then
			return args:iter()
		end
	else
		args = {...}
	end
	local i = 0
	return function ()
		i = i + 1
		return args[i]
	end
end
function Set:add(element)
	if not self.elements[element] then
		self.elements[element] = true
		self.size = self.size + 1
		return true
	end
	return false
end
function Set:addAll(...)
	local changed = false
	for value in Set.varIter(...) do
		changed = self:add(value) or changed
	end
	return changed
end
function Set:remove(element)
	if self.elements[element] then
		self.elements[element] = nil
		self.size = self.size - 1
		return true
	end
	return false
end
function Set:removeAll(...)
	local changed = false
	for value in Set.varIter(...) do
		changed = self:remove(value) or changed
	end
	return changed
end
function Set:retain(...)
	local newElements = {}
	local newSize = 0
	for value in Set.varIter(...) do
		if self.elements[value] and not newElements[value] then
			newElements[value] = true
			newSize = newSize + 1
		end
	end
	self.elements = newElements
	local changed = self.size == newSize
	self.size = newSize
	return changed
end
function Set:contains(element)
	return self.elements[element]
end
function Set:containsAll(...)
	for value in Set.varIter(...) do
		if not self.elements[value] then
			return false
		end
	end
	return true
end
function Set:containsAny(...)
	for value in Set.varIter(...) do
		if self.elements[value] then
			return true
		end
	end
	return false
end
function Set:clear()
	self.elements = {}
	self.size = 0
end
function Set:clone()
	local clone = Set.new()
	clone:addAll(self)
	return clone
end
function Set:iter()
	return Set.iterator, self.elements, nil
end
function Set:unpack(lastElement)
	local nextElement = next(self.elements, lastElement)
	if nextElement ~= nil then
		return nextElement, self:unpack(nextElement)
	end
end
Set.EMPTY = Set.new()

--A multi map class based on the Guava Multimap
local MultiMap = {
	mt = {},
	type = "multimap",
	iterator = function (invariantState, controlVariable)
		return next(invariantState, controlVariable)
	end
}
MultiMap.mt.__index = MultiMap
function MultiMap.new()
	local multiMap = {numKeys = 0, numValues = 0, map = {}}
	setmetatable(multiMap, MultiMap.mt)
	return multiMap
end
function MultiMap:put(key, value)
	local valueSet = self.map[key]
	if not valueSet then
		valueSet = Set.new()
		self.map[key] = valueSet
		self.numKeys = self.numKeys + 1
	end
	if valueSet:add(value) then
		self.numValues = self.numValues + 1
		return true
	end
	return false
end
function MultiMap:putAll(key, ...)
	local valueSet = self.map[key]
	if not valueSet then
		valueSet = Set.new()
		self.map[key] = valueSet
		self.numKeys = self.numKeys + 1
	end
	local beforeSize = valueSet.size
	local changed = valueSet:addAll(...)
	self.numValues = self.numValues + valueSet.size - beforeSize
	return changed
end
function MultiMap:get(key)
	return self.map[key] or Set.EMPTY
end
function MultiMap:containsKey(key)
	return self.map[key] ~= nil
end
function MultiMap:containsEntry(key, value)
	return self:get(key):contains(value)
end
function MultiMap:remove(key, value)
	local valueSet = self:get(key)
	local wasValueRemoved = valueSet:remove(value)
	if wasValueRemoved then
		self.numValues = self.numValues - 1
		if valueSet.size == 0 then
			self.map[key] = nil
			self.numKeys = self.numKeys - 1
		end
	end
	return wasValueRemoved
end
function MultiMap:removeAll(key)
	local previousValue = self.map[key]
	if previousValue then
		self.map[key] = nil
		self.numKeys = self.numKeys - 1
		self.numValues = self.numValues - previousValue.size
	end
	return previousValue or Set.EMPTY
end
function MultiMap:iter()
	return MultiMap.iterator, self.map, nil
end

--A class that holds a map of maps for convenience
local NestedMap = {
	mt = {},
	type = "nestedmap",
	iterator = function (invariantState, controlVariable)
		return next(invariantState, controlVariable)
	end
}
NestedMap.mt.__index = NestedMap
function NestedMap.new()
	local nestedMap = {map = {}}
	setmetatable(nestedMap, NestedMap.mt)
	return nestedMap
end
function NestedMap:put(key1, key2, value)
	local subMap = self.map[key1]
	if not subMap then
		subMap = {}
		self.map[key1] = subMap
	end
	local previousValue = subMap[key2]
	subMap[key2] = value
	return previousValue
end
function NestedMap:putAll(key1, table)
	local subMap = self.map[key1]
	if not subMap then
		subMap = {}
		self.map[key1] = subMap
	end
	local changed = false
	for key2, value in pairs(table) do
		changed = changed or subMap[key2] ~= value
		subMap[key2] = value
	end
	return changed
end
function NestedMap:get(key1, key2)
	local subMap = self.map[key1]
	if not subMap then
		return nil
	end
	return subMap[key2]
end
function NestedMap:getAll(key1)
	return self.map[key1] or NestedMap.EMPTY_TABLE
end
function NestedMap:containsKey(key1)
	return self.map[key1] ~= nil
end
function NestedMap:containsKeys(key1, key2)
	local subMap = self.map[key1]
	if not subMap then
		return false
	end
	return subMap[key2] ~= nil
end
function NestedMap:containsEntry(key1, key2, value)
	local subMap = self.map[key1]
	if not subMap then
		return false
	end
	return subMap[key2] == value
end
function NestedMap:remove(key1, key2)
	local subMap = self.map[key1]
	if not subMap then
		return nil
	end
	local previousValue = subMap[key2]
	subMap[key2] = nil
	return previousValue
end
function NestedMap:removeAll(key1)
	local previousValue = self.map[key1]
	if previousValue then
		self.map[key1] = nil
	end
	return previousValue or NestedMap.EMPTY_TABLE
end
function NestedMap:iter()
	return NestedMap.iterator, self.map, nil
end
NestedMap.EMPTY_TABLE = {}

-- ---- Util Functions & Variables ----
-- ------------------------------------

local function distanceSquared(x1, z1, x2, z2)
	return (x2-x1)*(x2-x1) + (z2-z1)*(z2-z1)
end

local function distance(x1, z1, x2, z2)
	return math.sqrt((x2-x1)*(x2-x1) + (z2-z1)*(z2-z1))
end

local function insertArrayIntoArray(valueArray, containerArray)
	for _, value in ipairs(valueArray) do
		table.insert(containerArray, value)
	end
end

local framesPerDay = fps * 3600 * 24
-- Gets the current game frame
local function getGameFrame()
	local frames, days = Spring.GetGameFrame()
	return frames + days * framesPerDay
end

-- Returns the closest update frame that is greater than the given frame
local function getNextUpdateFrame(frame)
	return (floor(frame / framesPerUpdate) + 1) * framesPerUpdate
end

-- Calls Spring.Log with the given arguments and widgetName
local function log(level, msg)
	Spring.Log(logWidgetName, level, msg)
end

--TODO remove
function dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end

-- /////////////////////////////
-- #endregion
-- /////////////////////////////

-- #region Mod Options

-- a set of unit def ids of all capture-qualified unit types
local captureQualifiedUnitDefIds = Set.new()

-- the MapArea defining the hill
local hillArea

-- whether or not players can build outside of their start area
local buildOutsideBoxes

-- defines who is allowed to build in the hill
--		1 = no one can ever build in the hill
--		2 = only the current king can build in the hill
--		3 = everyone can always build in the hill
local hillBuildRule

-- the total time needed as king to win in milliseconds
local winKingTime

-- winKingTime in frames
local winKingTimeFrames

-- the number of milliseconds an ally team must occupy the hill to capture it
local captureDelay

-- captureDelay in frames
local captureDelayFrames

-- if true, the king will only start loosing the hill once he leaves it; if false, he will start loosing it if anyone else enters it
local kingKeepsHill

-- whether units should be immune to damage in their start boxes
local noDamageInBoxes

-- whether all units in the hill will explode when the king changes
local explodeHillUnits

-- whether we should draw the start box outlines; only false if noDamageInBoxes is false and buildOutsideBoxes is true
local shouldDrawStartBoxes

-- #endregion

-- #region Main Variables

-- whether GameStart has been called
local gameStarted = getGameFrame() > 0

-- the last frame number that was passed into the GameFrame callin
local lastGameFrame = -1

-- teamId to allyTeamId for all teams
local teamToAllyTeam = {}

-- playerId to allyTeamId for all players
local playerToAllyTeam = {}

-- teamId to playerId (should only be one player per team)
local teamToPlayer = {}

-- playerId to teamId
local playerToTeam ={}

-- array of allyTeamIds
local allyTeams = {}

-- allyTeamId to index in allyTeams
local allyTeamIndices = {}

-- MultiMap of allyTeamId to set of teams
local allyTeamToTeams = MultiMap.new()

-- the number of ally teams
local numAllyTeams = 0

-- the total number of teams
local numTeams = 0

-- allyTeamId to RectMapArea defining the allyTeam's starting area
local startBoxes = {}

-- a table of allyTeamId to the average color of all the constituent teams
local allyTeamColors = {}

-- the user's playerId
local myPlayerId

-- the user's ally team
local myAllyTeam

-- the user's team
local myTeam

-- the user's start box as a RectMapArea object
local myStartBox

-- a set of all of the user's capture qualified units
local myCaptureQualifiedUnits = Set.new()

-- a set of all the user's building units in the hill
local myHillBuildings = Set.new()

-- a set of all the user's building units in his start box
local myStartBoxBuildings = Set.new()

-- allyTeamId to number of frames for which that team has held the hill
local allyTeamKingTime = {}

--The current king ally team's id.
local kingAllyTeam

--The frame on which the current king became king
local kingStartFrame

--The frame at which the current king will win if he remains king
local kingWinFrame = math.huge

-- the allyTeamId of the ally team currently in the process of capturing the hill
local capturingAllyTeam

-- the frame at which the current capturing process will be complete (counting up or down, see below)
local capturingCompleteFrame = 0

-- specifies the direction in which capturing progress is being made
-- true = up = progressing toward capturing the hill, false = down = losing progress that was previously made
local capturingCountingUp = false

-- a set of units that are currently counting down to be self-destructed. Used to block the user from
-- stopping a widget-issued self-destruct command
local selfDestructingUnits = Set.new()

-- The set of players that are actively participating in the KOTH widget and sending valid updates.
local activePlayers = Set.new()

-- Map of allyTeamId to the number of active players on that team
local allyTeamActivePlayerCount = {}

-- The frame up to which all updates have been processed and for which the local game state is valid
local currentStateFrame = -framesPerUpdate-- first increment to zero

-- MultiMap of frame to playerIDs that should be removed from the count of active players on the given frame
local playerDeactivationUpdates = MultiMap.new()

-- Set of my units that are damaging other ally team's start boxes. Used to force hold fire until they leave the box.
local damageInBoxUnits = Set.new()

-- MultiMap of game frame to playerIDs of disconnected players that should be deactivated on that game frame.
-- This queue is run asynchronously of the game state update processing, meaning the player will be deactivated on the
-- actual game frame specified, not when that frame's update is processed. (See PlayerRemoved callin)
local removedPlayerDeactivationQueue = MultiMap.new()

-- #endregion

-- #region UIMsg

local base94SymbolsString = "!\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
local base94Symbols = {}
local base94SymbolIndices = {}
for i = 1, #base94SymbolsString do
	local sym = string.sub(base94SymbolsString, i, i)
	base94Symbols[i] = sym
	base94SymbolIndices[sym] = i
end

local function intToBase94(num)
	if num < 0 then
		error("Cannot convert negative numbers to base94", 2)
	end
	
	num = floor(num + 0.5)
	local result = ""
	
	repeat
		result = base94Symbols[num % 94 + 1] .. result
		num = floor(num / 94)
	until num == 0
	
	return result
	
end

local function base94ToInt(str)
	local strLen = #str
	if strLen == 0 then
		error("Cannot convert empty string from base94", 2)
	end
	
	local result = 0
	
	for i = strLen, 1, -1 do
		local power = strLen - i
		local char = substring(str, i, i)
		result = result + (94^power) * (base94SymbolIndices[char] - 1)
	end
	
	return result;
	
end

-- A class that sends data to other clients via Spring.SendLuaUIMsg().
-- Each packet type has a single character for identifying itself when it is received.
local UIMsgPacket = {
	mt = {},
	prefix = "]",
	frameSuffix = " ",
	bodyDeserializers = {}
}
UIMsgPacket.mt.__index = UIMsgPacket
function UIMsgPacket.new(args)
	if not args.idChar or not args.typeId or not args.deserializeBody or not args.serializeBody then
		error("Missing one or more arguments for new UIMsgPacket", 2)
	end
	
	args.frame = args.frame or getNextUpdateFrame(getGameFrame())
	
	if not getmetatable(args) then
		setmetatable(args, UIMsgPacket.mt)
	end
	return args
end
function UIMsgPacket.setBodyDeserializer(idChar, bodyDeserializer)
	UIMsgPacket.bodyDeserializers[idChar] = bodyDeserializer
end
-- Deserializes a string into the data and the frame on which it was sent
function UIMsgPacket.deserialize(data)
	local idChar = substring(data, 2, 2)
	local frameSuffixIndex = findString(data, UIMsgPacket.frameSuffix, 4)
	local frameBase94 = substring(data, 3, frameSuffixIndex - 1)
	local frame = base94ToInt(frameBase94)
	return UIMsgPacket.bodyDeserializers[idChar](substring(data, frameSuffixIndex + 1), frame)
end
-- Serializes the data and frame on which it is sent into a string
function UIMsgPacket:serialize()
	return UIMsgPacket.prefix .. self.idChar .. intToBase94(self.frame) .. UIMsgPacket.frameSuffix .. self:serializeBody()
end
-- Sends the serialized value
function UIMsgPacket:send()
	Spring.SendLuaUIMsg(self:serialize())
end

-- A UIMsgPacket that is sent when a player damages another ally team's units inside their start box when noDamageInBoxes is enabled
local DamageInBoxUIPacket = {
	mt = {},
	idChar = "a",
	typeId = 1
}
setmetatable(DamageInBoxUIPacket, UIMsgPacket.mt)
DamageInBoxUIPacket.mt.__index = DamageInBoxUIPacket
function DamageInBoxUIPacket.new(args)
	if not args.attackerTeam or not args.attackerUnit then
		error("Missing one or more arguments for new DamageInBoxUIPacket", 2)
	end
	
	if not getmetatable(args) then
		setmetatable(args, DamageInBoxUIPacket.mt)
	end
	args = UIMsgPacket.new(args)
	return args
end
function DamageInBoxUIPacket.deserializeBody(body, frame)
	local subStrings = splitString(body, " ")
	return DamageInBoxUIPacket.new({frame = frame, attackerTeam = base94ToInt(subStrings[1]), attackerUnit = base94ToInt(subStrings[2])})
end
UIMsgPacket.setBodyDeserializer(DamageInBoxUIPacket.idChar, DamageInBoxUIPacket.deserializeBody)
function DamageInBoxUIPacket:serializeBody()
	return intToBase94(self.attackerTeam) .. " " .. intToBase94(self.attackerUnit)
end

-- A UIMsgPacket that is sent to deactivate the sender (used in widget:Shutdown)
local SelfDeactivationUIPacket = {
	mt = {},
	idChar = "b",
	typeId = 2
}
setmetatable(SelfDeactivationUIPacket, UIMsgPacket.mt)
SelfDeactivationUIPacket.mt.__index = SelfDeactivationUIPacket
function SelfDeactivationUIPacket.new(args)
	args = args or {}
	
	if not getmetatable(args) then
		setmetatable(args, SelfDeactivationUIPacket.mt)
	end
	args = UIMsgPacket.new(args)
	return args
end
function SelfDeactivationUIPacket.deserializeBody(body, frame)
	return SelfDeactivationUIPacket.new({frame = frame})
end
UIMsgPacket.setBodyDeserializer(SelfDeactivationUIPacket.idChar, SelfDeactivationUIPacket.deserializeBody)
function SelfDeactivationUIPacket:serializeBody()
	return ""
end

-- A UIMsgPacket that is sent at the beginning of the game to confirm that we are running this version of this widget
local VersionInitUIPacket = {
	mt = {},
	idChar = "c",
	typeId = 3
}
setmetatable(VersionInitUIPacket, UIMsgPacket.mt)
VersionInitUIPacket.mt.__index = VersionInitUIPacket
function VersionInitUIPacket.new(args)
	args = args or {}
	
	args.version = args.version or kothWidgetVersion
	
	if not getmetatable(args) then
		setmetatable(args, VersionInitUIPacket.mt)
	end
	args = UIMsgPacket.new(args)
	return args
end
function VersionInitUIPacket.deserializeBody(body, frame)
	return VersionInitUIPacket.new({frame = frame, version = base94ToInt(body)})
end
UIMsgPacket.setBodyDeserializer(VersionInitUIPacket.idChar, VersionInitUIPacket.deserializeBody)
function VersionInitUIPacket:serializeBody()
	return intToBase94(self.version)
end

-- Map of frame number to the number of players from whom we have received an update for that frame
local numReceivedPlayers = {}

-- Map of playerId to the frame number of the last frame for which we have received an update from that player
local latestReceivedFrames = {}

-- Map of frame number to map of playerId to whether they are in the hill on the given frame
local playerUpdates = NestedMap.new()

-- #endregion

--//////////////////////////
-- #region       UI
--//////////////////////////

-- UI Variables
-- ------------

--Constants
local flowUIDrawElement

--Contains the position of the UI box. Used for WG API function 'GetPosition'
local uiBoxPosition

--Contains the position of the UI box above the main UI box that contains additional information
local addInfoBoxPosition

--Whether the additional info UI box is hidden
local addInfoBoxHidden = false

--Contains the position of the player list widget UI box. This is used to check for
--clicks on the player list and update our box size whenever it is clicked since
--clicking certain buttons in the player list causes it to change size
local playerListPosition

--The shaders for the progress bars
local progressBarShader = gl.CreateShader({vertex = VFS.LoadFile(progressBarVertexShaderPath),
												fragment = VFS.LoadFile(progressBarFragmentShaderPath)})
--Spring.Log("KingOfTheHill", "error", "Shader Log: \n" .. gl.GetShaderLog())

--The shaders for the area outlines
local mapAreaShader = gl.CreateShader({vertex = VFS.LoadFile(mapAreaVertexShaderPath):gsub("//##UBO##", gl.GetEngineUniformBufferDef(0)),
											fragment = VFS.LoadFile(mapAreaFragmentShaderPath)})
--Spring.Log("KingOfTheHill", "error", "Shader Log: \n" .. gl.GetShaderLog())

--A UBO containing an array of ally team colors
local allyTeamColorsUBO

--The UIElement for the box containing the progress bars
local uiBoxElement

-- allyTeamId to UIBar object for that team's progress bar
local allyTeamProgressBars = {}

-- The UIBar for the progress bar indicating the capture delay
local captureProgressBar

-- allyTeamId to UITextTimer object for that team's progress timer
local allyTeamProgressTimers = {}

-- The UITextTimer for the timer indicating the capture delay
local captureProgressTimer

-- The UIElement for the box containing additional information
local addInfoBoxElement

-- teamId to the UITextElement for that team's name in the additional info UI box
local teamNameAddInfoTexts = {}

-- Arrays of UITextElements for the mod options shown in the additional info box
local modOptionNameAddInfoTexts = {}
local modOptionValueAddInfoTexts = {}

-- The regular font
local exo2Font
-- The semi-bold font
local exo2SemiBoldFont

-- Used to update the position of the UI box multiple times after the screen is resized
-- since the ordering of the size updates from the lower widgets is unknown to me
local screenResizeCountdown = 0

-- UI Util Functions
-- -----------------

-- Converts the given x and y screen coordinates to clip space [-1, 1]
local function convertToClipSpace(x, y)
	if x and y then
		return 2*x/vsx - 1, 2*y/vsy - 1
	elseif x then
		return 2*x/vsx - 1
	elseif y then
		return 2*y/vsy - 1
	else
		return nil
	end
end

-- Prevents switching to a shader if it is currently active
local currentShader = nil
local function useShader(shader)
	if currentShader ~= shader then
		gl.UseShader(shader)
		currentShader = shader
	end
end

-- Prevent rebinding UBO if it is already bound
local allyTeamColorsUBOBound = false
local function bindAllyTeamColorsUBO()
	if allyTeamColorsUBOBound then
		return
	end
	allyTeamColorsUBO:BindBufferRange(6, false, false, GL.UNIFORM_BUFFER)
	allyTeamColorsUBOBound = true
end
local function unbindAllyTeamColorsUBO()
	if not allyTeamColorsUBOBound then
		return
	end
	allyTeamColorsUBO:UnbindBufferRange(6, false, false, GL.UNIFORM_BUFFER)
	allyTeamColorsUBOBound = false
end

--Prevent changing line width if already set to desired value
local currentLineWidth;
local function setLineWidth(width)
	if currentLineWidth ~= width then
		gl.LineWidth(width)
		currentLineWidth = width
	end
end
local function resetLineWidth()
	currentLineWidth = -1
end

-- UI Classes
-- ----------

-- This class is used to set the value of an OpenGL uniform. Its main purpose is to
-- prevent setting the uniform to the same value multiple times. Each instance of this
-- class represents one uniform value or index in a uniform array.
local UniformValue = {
	mt = {},
	Type = {INT = 1, FLOAT = 2, VECTOR = 3, ARRAY = 4, MATRIX = 5}
}
UniformValue.mt.__index = UniformValue
function UniformValue.new(args)
	args = args or {}
	if not args.name or not args.shader or not args.value or not args.type or (args.type == UniformValue.Type.ARRAY and not args.arraySubtype) then
		error("Missing one or more arguments for new UniformValue", 2)
	end
	
	args.lastValue = nil
	args.location = args.location or gl.GetUniformLocation(args.shader, args.name)
	args.invalid = true
	
	if not getmetatable(args) then
		setmetatable(args, UniformValue.mt)
	end
	return args
end
function UniformValue:update()
	if not self.invalid then
		return
	end
	useShader(self.shader)
	if self.type == UniformValue.Type.FLOAT then
		gl.Uniform(self.location, self.value)
	elseif self.type == UniformValue.Type.INT then
		gl.UniformInt(self.location, self.value)
	elseif self.type == UniformValue.Type.VECTOR then
		gl.Uniform(self.location, table.unpack(self.value))
	elseif self.type == UniformValue.Type.ARRAY then
		gl.UniformArray(self.location, self.arraySubtype, self.value)
	elseif self.type == UniformValue.Type.MATRIX then
		gl.UniformMatrix(self.location, self.value)
	end
	self.lastValue = self.value
	self.invalid = false
end
function UniformValue:set(newValue)
	self.value = newValue
	self.invalid = not self:equalsLastValue(newValue)
end
function UniformValue:setAndUpdate(newValue)
	self:set(newValue)
	self:update()
end
function UniformValue:equalsLastValue(newValue)
	if self.type == UniformValue.Type.VECTOR or self.type == UniformValue.Type.ARRAY or self.type == UniformValue.Type.MATRIX then
		for index, value in ipairs(self.lastValue) do
			if value ~= newValue[index] then
				return false
			end
		end
		return true
	end
	return self.lastValue == newValue
end

-- A class for a generic UI element, by default, renders a basic FlowUI box. This class and all its
-- subclasses below update the position and data associated with the element on a draw call whenever
-- it is invalidated.
local UIElement = {
	mt = {}
}
UIElement.mt.__index = UIElement
function UIElement.new(args)
	args = args or {}
	
	args.top = args.top or 0
	args.bottom = args.bottom or 0
	args.left = args.left or 0
	args.right = args.right or 0
	args.children = args.children or Set.new()
	if args.parent then
		args.parent.children:add(args)
	end
	args.width = args.right - args.left
	args.height = args.top - args.bottom
	args.positionInvalid = true
	args.dataInvalid = true
	
	if not getmetatable(args) then
		setmetatable(args, UIElement.mt)
	end
	return args
end
-- Meant to be called every frame in draw callin. Updates and draws this element
function UIElement:drawFrame()
	if self.positionInvalid then
		self:updatePosition()
	end
	if self.dataInvalid then
		self:updateData()
	end
	self:draw()
end
-- draws this UI element
function UIElement:draw()
	gl.CallList(self.displayList)
end
-- updates the position data of the UI element (i.e. VBO vertices)
function UIElement:updatePosition()
	self:updateData()
	self.positionInvalid = false
end
-- updates the data associated with this UI element (i.e. UBO, SSBO, etc.)
function UIElement:updateData()
	gl.DeleteList(self.displayList)
	self.displayList = gl.CreateList(function ()
		flowUIDrawElement(self.left, self.bottom, self.right, self.top, self.cornerTL, self.cornerTR, self.cornerBR, self.cornerBL, self.ptl, self.ptr, self.pbr, self.pbl, self.opacity, self.color1, self.color2, self.bgpadding)
	end)
	self.dataInvalid = false
end
-- Invalidates the position data of this UI element (and all its children) so that it will be updated next render
function UIElement:invalidatePosition()
	self.positionInvalid = true
	for child in self.children:iter() do
		child:invalidatePosition()
	end
end
-- Invalidates the data associated with this UI element so that it will be updated next render
function UIElement:invalidateData()
	self.dataInvalid = true
end
function UIElement:setPos(args)
	if not ((args.top and args.top ~= self.top) or (args.right and args.right ~= self.right) or (args.bottom and args.bottom ~= self.bottom)
		or (args.left and args.left ~= self.left)) then
		return
	end
	self.top = args.top or self.top
	self.left = args.left or self.left
	self.bottom = args.bottom or self.bottom
	self.right = args.right or self.right
	self.width = self.right - self.left
	self.height = self.top - self.bottom
	self:invalidatePosition()
end
function UIElement:isPointInside(x, y)
	return x >= self.left and x <= self.right and y >= self.bottom and y <= self.top
end

-- A class for each UI progress bar
local UIBar = {
	mt = {},
	ProgressBarData = UniformValue.new({name = "progressBarData", shader = progressBarShader, value = 0, type = UniformValue.Type.INT}),
	Flags = {CAPTURE_BAR = 0x00800000, DISQUALIFIED = 0x00400000}
}
setmetatable(UIBar, UIElement.mt)
UIBar.mt.__index = UIBar
function UIBar.new(args)
	args.flags = args.flags or 0
	if not args.allyTeam and (not args.flags or math.bit_and(args.flags, UIBar.Flags.CAPTURE_BAR) == 0) then
		error("Missing one or more arguments for new UIBar", 2)
	end
	
	args.allyTeamIndex = (allyTeamIndices[args.allyTeam] or 1) - 1
	args.shader = args.shader or progressBarShader
	local progressIndex = math.bit_and(args.flags, UIBar.Flags.CAPTURE_BAR) ~= 0 and fragmentShaderMaxTeams or args.allyTeamIndex
	args.progress = UniformValue.new({name = "progress[" .. progressIndex .. "]", shader = args.shader, value = args.progress or 0, type = UniformValue.Type.FLOAT})
	args.vbo = gl.GetVBO(GL.ARRAY_BUFFER, false)
	args.vbo:Define(4, {{id = 0, name = "position", size = 2}, {id = 1, name = "uv", size = 2}})
	args.vao = gl.GetVAO()
	args.vao:AttachVertexBuffer(args.vbo)
	
	if not getmetatable(args) then
		setmetatable(args, UIBar.mt)
	end
	args = UIElement.new(args)
	return args
end
function UIBar:draw()
	useShader(self.shader)
	bindAllyTeamColorsUBO()
	UIBar.ProgressBarData:setAndUpdate(math.bit_or(self.allyTeamIndex, self.flags))
	self.vao:DrawArrays(GL.TRIANGLE_STRIP)
end
function UIBar:updatePosition()
	--Progress bar region clip positions. Floor and ceil to round to nearest pixel to prevent fractional pixel artifacts
	local left = convertToClipSpace(floor(self.left), nil)
	local right = convertToClipSpace(ceil(self.right), nil)
	local top = convertToClipSpace(nil, ceil(self.top))
	local bottom = convertToClipSpace(nil, floor(self.bottom))
	--Triangle strip vertices with uv
	local vertices = {
		left, top, 0, 1,
		left, bottom, 0, 0,
		right, top, 1, 1,
		right, bottom, 1, 0
	}
	self.vbo:Upload(vertices)
	self.positionInvalid = false
end
function UIBar:updateData()
	self.progress:update()
	self.dataInvalid = false
end
function UIBar:setProgress(progress)
	progress = max(min(progress, 1), 0)
	if abs(progress - self.progress.lastValue) * self.width >= 1 then
		self.progress:set(progress)
		self:invalidateData()
	end
end
function UIBar:setAllyTeam(allyTeamId)
	self.allyTeamIndex = (allyTeamIndices[allyTeamId] or 1) - 1
end
function UIBar:setDisqualified(value)
	local flag = UIBar.Flags.DISQUALIFIED
	if value then
		self.flags = math.bit_or(self.flags, flag)
	else
		self.flags = math.bit_and(self.flags, math.bit_inv(flag))
	end
end

-- A class for map area outlines rendered on the world
local UIMapArea = {
	mt = {},
	MapAreaData = UniformValue.new({name = "mapAreaData", shader = mapAreaShader, value = 0, type = UniformValue.Type.INT}),
	Flags = {HILL_AREA = 0x00800000}
}
setmetatable(UIMapArea, UIElement.mt)
UIMapArea.mt.__index = UIMapArea
function UIMapArea.new(args)
	args.flags = args.flags or 0
	if not args.allyTeam and (not args.flags or math.bit_and(args.flags, UIMapArea.Flags.HILL_AREA) == 0) then
		error("Missing one or more arguments for new UIMapArea", 2)
	end
	
	args.allyTeamIndex = (allyTeamIndices[args.allyTeam] or fragmentShaderMaxTeams + 1) - 1
	args.lineWidth = args.lineWidth or mapAreaLineWidth
	args.shader = args.shader or mapAreaShader
	args.vbo = gl.GetVBO(GL.ARRAY_BUFFER, false)
	args.vbo:Define(#args.xzVertices, {{id = 0, name = "position", size = 3}})
	args.vao = gl.GetVAO()
	args.vao:AttachVertexBuffer(args.vbo)
	
	if not getmetatable(args) then
		setmetatable(args, UIMapArea.mt)
	end
	args = UIElement.new(args)
	return args
end
function UIMapArea:draw()
	useShader(self.shader)
	bindAllyTeamColorsUBO()
	setLineWidth(self.lineWidth)
	UIMapArea.MapAreaData:setAndUpdate(math.bit_or(self.allyTeamIndex, self.flags))
	self.vao:DrawArrays(GL.LINE_LOOP)
end
function UIMapArea:updatePosition()
	local vertices = {}
	for index, xzVertex in ipairs(self.xzVertices) do
		local offset = index * 3 - 2
		local x = xzVertex[1]
		local z = xzVertex[2]
		vertices[offset] = x
		vertices[offset + 1] = Spring.GetGroundHeight(x, z) + mapAreaLineVertexVerticalShift--TODO test what happens when outline goes outside map and make this work on water
		vertices[offset + 2] = z
	end
	self.vbo:Upload(vertices)
	self.positionInvalid = false
end
function UIMapArea:updateData()
	self.dataInvalid = false
end
function UIMapArea:setAllyTeam(allyTeamId)
	self.allyTeamIndex = (allyTeamIndices[allyTeamId] or fragmentShaderMaxTeams + 1) - 1
end
function UIMapArea:isRectIntersectingOutline(x1, z1, x2, z2)
	local corners = {x1, z1, x1, z2, x2, z1, x2, z2}
	local isInside = false
	local isOutside = false
	for i = 1, 7, 2 do
		local isPointInside = self:isPointInside(corners[i], corners[i + 1])
		isInside = isInside or isPointInside
		isOutside = isOutside or not isPointInside
		if isInside and isOutside then
			return true
		end
	end
	return false
end

local RectMapArea = {
	mt = {},
	type = "rect"
}
setmetatable(RectMapArea, UIMapArea.mt)
RectMapArea.mt.__index = RectMapArea
function RectMapArea.new(args)
	if not args.left or not args.right or not args.top or not args.bottom then
		error("Missing one or more arguments for new RectMapArea", 2)
	end
	
	args.centerX = (args.left + args.right) / 2
	args.centerZ = (args.top + args.bottom) / 2
	args.xSize = args.right - args.left
	args.zSize = args.bottom - args.top
	args.xHalfSize = args.xSize / 2
	args.zHalfSize = args.zSize / 2
	
	--Populate the XZ vertex coordinates
	local left, right, top, bottom, xSize, zSize = args.left, args.right, args.top, args.bottom, args.xSize, args.zSize
	local numVertices = min(ceil((xSize * 2 + zSize * 2) / mapAreaPreferredSpacing), mapAreaMaxVertices)
	local numXPoints = floor((numVertices - 4) * (xSize / (xSize + zSize)) / 2)
	local numZPoints = floor(((numVertices - 4) - (numXPoints * 2)) / 2)
	local xDelim = (xSize + 1) / numXPoints
	local zDelim = (zSize + 1) / numZPoints
	local topSide = {{left, top}}--the vertices along the top edge starting with the top left corner moving to the right not including the top right corner
	local bottomSide = {{right, bottom}}--the vertices along the bottom edge starting with the bottom right corner moving to the left not including the bottom left corner
	for i = 1, numXPoints, 1 do
		table.insert(topSide, {left + (xDelim * i), top})
		table.insert(bottomSide, {right - (xDelim * i), bottom})
	end
	local rightSide = {{right, top}}--the vertices along the right edge starting with the top right corner moving down not including the bottom right corner
	local leftSide = {{left, bottom}}--the vertices along the left edge starting with the bottom left corner moving up not including the top left corner
	for i = 1, numZPoints, 1 do
		table.insert(rightSide, {right, top + (zDelim * i)})
		table.insert(leftSide, {left, bottom - (zDelim * i)})
	end
	local xzVertices = {}
	insertArrayIntoArray(topSide, xzVertices)
	insertArrayIntoArray(rightSide, xzVertices)
	insertArrayIntoArray(bottomSide, xzVertices)
	insertArrayIntoArray(leftSide, xzVertices)
	args.xzVertices = xzVertices
	
	if not getmetatable(args) then
		setmetatable(args, RectMapArea.mt)
	end
	args = UIMapArea.new(args)
	return args
end
function RectMapArea:isPointInside(x, z)
	return x >= self.left and x <= self.right and z <= self.bottom and z >= self.top
end
function RectMapArea:isBuildingInside(x, z, sizeX, sizeZ)
	local top, right, bottom, left = z - sizeZ/2, x + sizeX/2, z + sizeZ/2, x - sizeX/2
	return top >= self.top and right <= self.right and bottom <= self.bottom and left >= self.left
end
function RectMapArea:isBuildingOverlapping(x, z, sizeX, sizeZ)
	local buildingTop, buildingRight, buildingBottom, buildingLeft = z - sizeZ/2, x + sizeX/2, z + sizeZ/2, x - sizeX/2
	local overlapTop, overlapRight, overlapBottom, overlapLeft = self.top - sizeZ, self.right + sizeX, self.bottom + sizeZ, self.left - sizeX
	return buildingTop >= overlapTop and buildingRight <= overlapRight and buildingBottom <= overlapBottom and buildingLeft >= overlapLeft
end
function RectMapArea:isCircleOverlapping(x, z, radius)
	local dx = abs(x - self.centerX)
	local dz = abs(z - self.centerZ)
	local xHalfSize = self.xHalfSize
	local zHalfSize = self.zHalfSize
	if dx > xHalfSize + radius then return false end
	if dz > zHalfSize + radius then return false end
	if dx <= xHalfSize then return true end
	if dz <= zHalfSize then return true end
	return distanceSquared(dx, dz, xHalfSize, zHalfSize) <= radius * radius
end

local CircleMapArea = {
	mt = {},
	type = "circle"
}
setmetatable(CircleMapArea, UIMapArea.mt)
CircleMapArea.mt.__index = CircleMapArea
function CircleMapArea.new(args)
	if not args.x or not args.z or not args.radius then
		error("Missing one or more arguments for new CircleMapArea", 2)
	end
	
	args.circumference = 2 * math.pi * args.radius
	args.radiusSquared = args.radius * args.radius
	
	--Populate the XZ vertex coordinates
	args.xzVertices = {}
	local numVertices = min(ceil(args.circumference / mapAreaPreferredSpacing), mapAreaMaxVertices)
	local angleDelim = 2 * math.pi / numVertices
	for i = 0, 2 * math.pi, angleDelim do
		table.insert(args.xzVertices, {args.x + (args.radius * math.cos(i)), args.z + (args.radius * math.sin(i))})
	end
	
	if not getmetatable(args) then
		setmetatable(args, CircleMapArea.mt)
	end
	args = UIMapArea.new(args)
	return args
end
function CircleMapArea:isPointInside(x, z)
	return distanceSquared(x, z, self.x, self.z) <= self.radiusSquared
end
function CircleMapArea:isBuildingInside(x, z, sizeX, sizeZ)
	local top, right, bottom, left = z - sizeZ/2, x + sizeX/2, z + sizeZ/2, x - sizeX/2
	return self:isPointInside(left, top) and self:isPointInside(right, top) and self:isPointInside(right, bottom) and self:isPointInside(left, bottom)
end
function CircleMapArea:isBuildingOverlapping(x, z, sizeX, sizeZ)
	local top, right, bottom, left = z - sizeZ/2, x + sizeX/2, z + sizeZ/2, x - sizeX/2
	return self:isPointInside(left, top) or self:isPointInside(right, top) or self:isPointInside(right, bottom) or self:isPointInside(left, bottom)
end
function CircleMapArea:isCircleOverlapping(x, z, radius)
	local sumRadius = self.radius + radius
	return distanceSquared(x, z, self.x, self.z) <= sumRadius * sumRadius
end

-- A class for basic UI text
local UITextElement = {
	mt = {},
	TextAlignment = {
		LEFT = 1,
		CENTER = 2,
		RIGHT = 3,
	},
	VerticalAlignment = {
		BASELINE = 1,
		CENTER = 2,
	}
}
setmetatable(UITextElement, UIElement.mt)
UITextElement.mt.__index = UITextElement
function UITextElement.new(args)
	if not args.text then
		error("Missing one or more arguments for new UITextElement", 2)
	end
	
	args.fontSize = args.fontSize or fontSizes.default
	args.bold = args.bold or false
	args.color = args.color or fontColors.white
	args.onColor = args.onColor or args.color
	args.offColor = args.offColor or fontColors.fadedGray
	args.textAlignment = args.textAlignment or UITextElement.TextAlignment.LEFT
	args.verticalAlignment = args.verticalAlignment or UITextElement.VerticalAlignment.BASELINE
	args.outline = args.outline or false
	args.fontFlags = ""
	if args.textAlignment == UITextElement.TextAlignment.RIGHT then
		args.fontFlags = args.fontFlags .. "r"
	elseif args.textAlignment == UITextElement.TextAlignment.CENTER then
		args.fontFlags = args.fontFlags .. "c"
	end
	if args.verticalAlignment == UITextElement.VerticalAlignment.CENTER then
		args.fontFlags = args.fontFlags .. "v"
	else
		args.fontFlags = args.fontFlags .. "x"
	end
	if args.outline then
		args.fontFlags = args.fontFlags .. "o"
	end
	
	if not getmetatable(args) then
		setmetatable(args, UITextElement.mt)
	end
	args = UIElement.new(args)
	return args
end
function UITextElement:updatePosition()
	if self.textAlignment == UITextElement.TextAlignment.RIGHT then
		self.x = self.right
	elseif self.textAlignment == UITextElement.TextAlignment.CENTER then
		self.x = self.left + self.width/2
	else
		self.x = self.left
	end
	if self.verticalAlignment == UITextElement.VerticalAlignment.CENTER then
		self.y = self.bottom + self.height/2
	else
		self.y = self.bottom
	end
	self:updateData()
	self.positionInvalid = false
end
function UITextElement:updateData()
	--Get font in here because it is deleted whenever the view resizes
	local font = self.bold and exo2SemiBoldFont or exo2Font
	gl.DeleteList(self.displayList)
	self.displayList = gl.CreateList(function ()
		font:SetTextColor(self.color)
		font:Print(self.text, self.x, self.y, self.fontSize, self.fontFlags)
	end)
	self.dataInvalid = false
end
function UITextElement:setText(text)
	if text ~= self.text then
		self.text = text
		self:invalidateData()
	end
end
function UITextElement:setFontSize(size)
	if size ~= self.fontSize then
		self.fontSize = size
		self:invalidateData()
	end
end
function UITextElement:setColor(color)
	if color ~= self.color then
		self.color = color
		self:invalidateData()
	end
end
function UITextElement:setColorOnOff(on)
	self:setColor(on and self.onColor or self.offColor)
end

-- A class for the timer next to each progress bar (counts down)
local UITextTimer = {
	mt = {}
}
setmetatable(UITextTimer, UITextElement.mt)
UITextTimer.mt.__index = UITextTimer
function UITextTimer.new(args)
	if not args.totalTimeSecs then
		error("Missing one or more arguments for new UITextTimer", 2)
	end
	
	args.text = args.text or "--:--"
	args.fontSize = args.fontSize or fontSizes.timers
	args.verticalAlignment = args.verticalAlignment or UITextElement.VerticalAlignment.CENTER
	args.currentTimeSecs = ceil(args.totalTimeSecs)
	
	if not getmetatable(args) then
		setmetatable(args, UITextTimer.mt)
	end
	args = UITextElement.new(args)
	
	return args
end
function UITextTimer:updateData()
	local minutes = floor(self.currentTimeSecs / 60)
	local seconds = self.currentTimeSecs % 60
	local timeString
	if minutes > 0 then
		local secondsString = tostring(seconds)
		if seconds < 10 then
			secondsString = "0" .. secondsString
		end
		timeString = tostring(minutes) .. ":" .. secondsString
	else
		timeString = tostring(seconds) .. "s"
	end
	self:setText(timeString)
	
	UITextElement.updateData(self)
end
function UITextTimer:setProgress(progress)
	progress = max(min(progress, 1), 0)
	local newTimeSecs = ceil((1 - progress) * self.totalTimeSecs)
	if newTimeSecs ~= self.currentTimeSecs then
		self.progress = progress
		self.currentTimeSecs = newTimeSecs
		self:invalidateData()
	end
end
function UITextTimer:setDisqualified(value)
	self:setColorOnOff(not value)
end

--///////////////
-- #endregion
--///////////////

-- Returns the name of the player if the playernames widget is available, otherwise returns "PlayerID: <playerId>"
local function getPlayerName(playerId)
	local playerNames = WG.playernames
	if playerNames then
		local playerName = playerNames.getPlayername(playerId)
		if playerName then
			return playerName
		end
	end
	return "PlayerID: " .. tostring(playerId)
end

-- Returns the player name of the player on the team if it is not an ai team and the playernames widget is available,
-- otherwise returns the AI name if there is an AI on the team, otherwise returns "TeamID: <teamId>"
local function getTeamName(teamId)
	local playerId = teamToPlayer[teamId]
	if playerId then
		local playerNames = WG.playernames
		if playerNames then
			local playerName = playerNames.getPlayername(playerId)
			if playerName then
				return playerName
			end
		end
	end
	local aiName = Spring.GetGameRulesParam("ainame_" .. teamId) or select(4, Spring.GetAIInfo(teamId))
	if aiName then
		return BAR.I18N("ui.playersList.aiName", {name = aiName}) or aiName
	end
	return "TeamID: " .. tostring(teamId)
end

-- Adds the chat line if WG.chat is available.
-- Returns true if the chat line was added.
local function addChatLine(gameFrame, text)
	local chat = WG.chat
	if chat then
		chat.addChatLine(gameFrame, LINE_TYPE_SYSTEM, "KOTH", "[KOTH]", text)
		return true
	end
	return false
end

-- Finds the text between two tweakDefsModOptionsDelimiters in the string
local function extractModOptionsCode(luaString)
    local _, startIndex = findString(luaString, tweakDefsModOptionsDelimiter, 1, true)
	if not startIndex then
		return nil
	end
	startIndex = startIndex + 1
	local endIndex = findString(luaString, tweakDefsModOptionsDelimiter, startIndex, true)
	if not endIndex then
		return nil
	end
	endIndex = endIndex - 1
    return substring(luaString, startIndex, endIndex)
end

-- Loads the mod options from the KOTHModoptions table or uses default values if provided options are invalid
local function loadModOptions()
	
	if type(KOTHModoptions) ~= "table" then
		log("warning", "Tweak defs mod options code did not set global 'KOTHModoptions' to a table value; resorting to default mod options")
		KOTHModoptions = defaultModOptions
	end
	
	if type(KOTHModoptions.captureQualifiedUnitNames) ~= "table" then
		log("warning", "KOTHModoptions table does not contain a key 'captureQualifiedUnitNames' that maps to a table value; resorting to default capture-qualified units")
		KOTHModoptions.captureQualifiedUnitNames = defaultModOptions.captureQualifiedUnitNames
	end
	local loadCaptureQualifiedUnits = function()
		for _, unitName in ipairs(KOTHModoptions.captureQualifiedUnitNames) do
			local unitDef = UnitDefNames[unitName]
			if unitDef then
				captureQualifiedUnitDefIds:add(unitDef.id)
			else
				log("warning", "Unrecognized capture-qualified unit name: " .. unitName .. "; ignoring")
			end
		end
	end
	loadCaptureQualifiedUnits()
	if captureQualifiedUnitDefIds.size == 0 then
		log("warning", "No valid capture-qualified units were found; resorting to default capture-qualified units")
		KOTHModoptions.captureQualifiedUnitNames = defaultModOptions.captureQualifiedUnitNames
		loadCaptureQualifiedUnits()
	end
	
	if type(KOTHModoptions.hillAreaArgs) ~= "table" then
		log("warning", "KOTHModoptions table does not contain a key 'hillAreaArgs' that maps to a table value; resorting to default hill area")
		KOTHModoptions.hillAreaArgs = defaultModOptions.hillAreaArgs
	end
	
	if KOTHModoptions.hillAreaArgs.type == "rect" then
		for _, key in ipairs({"left", "top", "right", "bottom"}) do
			local value = KOTHModoptions.hillAreaArgs[key]
			if type(value) ~= "number" then
				log("warning", "Table 'hillAreaArgs' in KOTHModoptions does not contain a key '" .. key .. "' that maps to a number value; resorting to default hill area")
				KOTHModoptions.hillAreaArgs = defaultModOptions.hillAreaArgs
				break
			end
			if value < 0 or value > 1 then
				log("warning", "The value of '" .. key .. "' in 'hillAreaArgs' is out of the range [0, 1]; these values should be proportions of the map size; ignoring")
			end
		end
	elseif KOTHModoptions.hillAreaArgs.type == "circle" then
		for _, key in ipairs({"x", "z", "radius"}) do
			local value = KOTHModoptions.hillAreaArgs[key]
			if type(value) ~= "number" then
				log("warning", "Table 'hillAreaArgs' in KOTHModoptions does not contain a key '" .. key .. "' that maps to a number value; resorting to default hill area")
				KOTHModoptions.hillAreaArgs = defaultModOptions.hillAreaArgs
				break
			end
			if value < 0 or value > 1 then
				log("warning", "The value of '" .. key .. "' in 'hillAreaArgs' is out of the range [0, 1]; these values should be proportions of the map size; ignoring")
			end
		end
	else
		log("error", "Unsupported hill area type: " .. KOTHModoptions.hillAreaArgs.type .. "; resorting to default hill area")
		KOTHModoptions.hillAreaArgs = defaultModOptions.hillAreaArgs
	end
	
	local hillAreaArgs = KOTHModoptions.hillAreaArgs
	local absHillAreaArgs = {}
	if hillAreaArgs.type == "rect" then
		absHillAreaArgs = {type = "rect", left = hillAreaArgs.left*mapSizeX, top = hillAreaArgs.top*mapSizeZ, right = hillAreaArgs.right*mapSizeX, bottom = hillAreaArgs.bottom*mapSizeZ}
	else
		absHillAreaArgs = {type = "circle", x = hillAreaArgs.x*mapSizeX, z = hillAreaArgs.z*mapSizeZ, radius = hillAreaArgs.radius*min(mapSizeX, mapSizeZ)}
	end
	absHillAreaArgs.allyTeam = false
	absHillAreaArgs.flags = UIMapArea.Flags.HILL_AREA
	hillArea = absHillAreaArgs.type == "circle" and CircleMapArea.new(absHillAreaArgs) or RectMapArea.new(absHillAreaArgs)
	
	local validateBoolean = function(key)
		if type(KOTHModoptions[key]) ~= "boolean" then
			log("warning", "KOTHModoptions table does not contain a key '" .. key .. "' that maps to a boolean value; resorting to default " .. key)
			KOTHModoptions[key] = defaultModOptions[key]
		end
		return KOTHModoptions[key]
	end
	
	buildOutsideBoxes = validateBoolean("buildOutsideBoxes")
	
	if type(KOTHModoptions.hillBuildRule) ~= "number" or KOTHModoptions.hillBuildRule ~= floor(KOTHModoptions.hillBuildRule) or KOTHModoptions.hillBuildRule < 1 or KOTHModoptions.hillBuildRule > 3 then
		log("warning", "KOTHModoptions table does not contain a key 'hillBuildRule' that maps to an integer value in the range [1, 3]; resorting to default hillBuildRule")
		KOTHModoptions.hillBuildRule = defaultModOptions.hillBuildRule
	end
	hillBuildRule = KOTHModoptions.hillBuildRule
	
	local oneFrameMilliseconds = 1000/fps--1 frame in milliseconds
	local validateDurationMilliseconds = function(key)
		if type(KOTHModoptions[key]) ~= "number" or KOTHModoptions[key] < 0 then
			log("warning", "KOTHModoptions table does not contain a key '" .. key .. "' that maps to a positive number value; resorting to default " .. key)
			KOTHModoptions[key] = defaultModOptions[key]
		end
		if KOTHModoptions[key] < oneFrameMilliseconds then
			log("warning", "The value of '" .. key .. "' in KOTHModoptions is below 1 frame; resorting to 1 frame")
			KOTHModoptions[key] = oneFrameMilliseconds
		end
		return KOTHModoptions[key], floor(fps*KOTHModoptions[key]/1000 + 0.5)
	end
	
	winKingTime, winKingTimeFrames = validateDurationMilliseconds("winKingTime")
	
	captureDelay, captureDelayFrames = validateDurationMilliseconds("captureDelay")
	
	kingKeepsHill = validateBoolean("kingKeepsHill")
	
	noDamageInBoxes = validateBoolean("noDamageInBoxes")
	
	explodeHillUnits = validateBoolean("explodeHillUnits")
	
	shouldDrawStartBoxes = (not noDamageInBoxes) and buildOutsideBoxes
	
end

-- Parses the mod options from the tweak defs
local function parseModOptions()
	local modOptions = Spring.GetModOptions()
	local tweakDefs = modOptions.tweakdefs
	for i = 1, 30 do
		if tweakDefs and tweakDefs ~= "" then
			log("info", "Looking for KOTH mod options in tweakdefs" .. (i > 1 and i - 1 or ""))
			local tweakDefsLua = tweakDefs:base64Decode()
			local modOptionsLua = extractModOptionsCode(tweakDefsLua)
			if modOptionsLua then
				local loadedModOptionsFunction, loadError = loadstring(modOptionsLua, "KOTH ModOptions")
				if loadedModOptionsFunction then
					local success, callError = pcall(loadedModOptionsFunction)
					if success then
						loadModOptions()
						return true
					else
						log("error", callError)
					end
				else
					log("error", loadError)
				end
			end
		end
		tweakDefs = modOptions["tweakdefs" .. i]
	end
	log("info", "No valid KOTH mod options were found in tweak defs")
	return false
end

--Called when the addon is (re)loaded.
function widget:Initialize()

	--Disable this widget if KOTH game mode is not enabled
	if not parseModOptions() then
		log("info", "Disabling King of the Hill widget")
		widgetHandler.RemoveWidget()
		return
	end
	
	--Array for data in allyTeamColorsUBO
	local allyTeamColorsVec4Array = {}
	
	-- Initialize the box UIElements
	uiBoxElement = UIElement.new()
	addInfoBoxElement = UIElement.new()
	
	local gaiaAllyTeamID
	if Spring.GetGaiaTeamID() then
		gaiaAllyTeamID = select(6, Spring.GetTeamInfo(Spring.GetGaiaTeamID()))
	end
	
	--Populate per team data such as start boxes, average color, progress bars, cache maps, etc.
	local index = 0
	for _, allyTeamId in ipairs(Spring.GetAllyTeamList()) do
		if allyTeamId ~= gaiaAllyTeamID then
			index = index + 1
			allyTeams[index] = allyTeamId
			allyTeamIndices[allyTeamId] = index
			numAllyTeams = numAllyTeams + 1
			allyTeamKingTime[allyTeamId] = 0
			allyTeamActivePlayerCount[allyTeamId] = 0
			
			local xMin, zMin, xMax, zMax = Spring.GetAllyTeamStartBox(allyTeamId)
			local startBox = RectMapArea.new{left = xMin, top = zMin, right = xMax, bottom = zMax, allyTeam = allyTeamId}
			startBoxes[allyTeamId] = startBox
			
			local red, green, blue = 0, 0, 0
			local numTeamsOnAllyTeam = 0
			
			for _, teamId in ipairs(Spring.GetTeamList(allyTeamId)) do
				teamToAllyTeam[teamId] = allyTeamId
				
				-- color average computed using squares (https://youtu.be/LKnqECcg6Gw)
				local teamRed, teamGreen, teamBlue = Spring.GetTeamColor(teamId)
				red = red + teamRed ^ 2
				green = green + teamGreen ^ 2
				blue = blue + teamBlue ^ 2
				numTeamsOnAllyTeam = numTeamsOnAllyTeam + 1
				allyTeamToTeams:put(allyTeamId, teamId)
				
				local _, playerId, _, hasAI = Spring.GetTeamInfo(teamId, false)
				
				if not hasAI then
					playerToAllyTeam[playerId] = allyTeamId
					teamToPlayer[teamId] = playerId
					playerToTeam[playerId] = teamId
					latestReceivedFrames[playerId] = -framesPerUpdate-- first update will put it at zero
				end
				
				teamNameAddInfoTexts[teamId] = UITextElement.new({
					text = getTeamName(teamId),
					color = {teamRed, teamGreen, teamBlue, 1},
					offColor = fontColors.lessFadedGray,
					outline = true,
					fontSize = fontSizes.addInfoTeamNames,
					bold = true,
					parent = addInfoBoxElement
				})
				teamNameAddInfoTexts[teamId]:setColorOnOff(false)
			end
			
			numTeams = numTeams + numTeamsOnAllyTeam
			
			-- r g b a = 1 2 3 4
			local averageColor = {math.sqrt(red/numTeamsOnAllyTeam), math.sqrt(green/numTeamsOnAllyTeam), math.sqrt(blue/numTeamsOnAllyTeam), 1}
			allyTeamColors[allyTeamId] = averageColor
			
			allyTeamProgressBars[allyTeamId] = UIBar.new({allyTeam = allyTeamId, parent = uiBoxElement})
			allyTeamProgressTimers[allyTeamId] = UITextTimer.new({totalTimeSecs = winKingTime/1000, parent = uiBoxElement})
			
			if index <= fragmentShaderMaxTeams then
				local dataOffset = (index - 1) * 4
				for j = 1, 4, 1 do
					allyTeamColorsVec4Array[dataOffset + j] = averageColor[j]
				end
			end
		end
	end
	
	-- color gets set when a team starts capturing
	captureProgressBar = UIBar.new({flags = UIBar.Flags.CAPTURE_BAR, parent = uiBoxElement})
	captureProgressTimer = UITextTimer.new({totalTimeSecs = captureDelay/1000, parent = uiBoxElement})
	
	local hillBuildRuleAddInfoValues = {
		[1] = {text = "No One", color = fontColors.red},
		[2] = {text = "King Only", color = fontColors.yellow},
		[3] = {text = "Everyone", color = fontColors.green}
	}
	
	local booleanAddInfoValues = {
		[true] = {text = "Yes", color = fontColors.green},
		[false] = {text = "No", color = fontColors.red}
	}
	
	modOptionNameAddInfoTexts = {
		UITextElement.new({text = "Hill Build Rule: ", fontSize = fontSizes.addInfoModOptionNames, parent = addInfoBoxElement}),
		UITextElement.new({text = "King Keeps Hill: ", fontSize = fontSizes.addInfoModOptionNames, parent = addInfoBoxElement}),
		UITextElement.new({text = "Hill Buildings Explode: ", fontSize = fontSizes.addInfoModOptionNames, parent = addInfoBoxElement}),
		UITextElement.new({text = "Immune in Start Box: ", fontSize = fontSizes.addInfoModOptionNames, parent = addInfoBoxElement})
	}
	
	modOptionValueAddInfoTexts = {
		UITextElement.new({
			text = hillBuildRuleAddInfoValues[hillBuildRule].text,
			color = hillBuildRuleAddInfoValues[hillBuildRule].color,
			textAlignment = UITextElement.TextAlignment.RIGHT,
			outline = true,
			fontSize = fontSizes.addInfoModOptionValues,
			bold = true,
			parent = addInfoBoxElement
		}),
		UITextElement.new({
			text = booleanAddInfoValues[kingKeepsHill].text,
			color = booleanAddInfoValues[kingKeepsHill].color,
			textAlignment = UITextElement.TextAlignment.RIGHT,
			outline = true,
			fontSize = fontSizes.addInfoModOptionValues,
			bold = true,
			parent = addInfoBoxElement
		}),
		UITextElement.new({
			text = booleanAddInfoValues[explodeHillUnits].text,
			color = booleanAddInfoValues[explodeHillUnits].color,
			textAlignment = UITextElement.TextAlignment.RIGHT,
			outline = true,
			fontSize = fontSizes.addInfoModOptionValues,
			bold = true,
			parent = addInfoBoxElement
		}),
		UITextElement.new({
			text = booleanAddInfoValues[noDamageInBoxes].text,
			color = booleanAddInfoValues[noDamageInBoxes].color,
			textAlignment = UITextElement.TextAlignment.RIGHT,
			outline = true,
			fontSize = fontSizes.addInfoModOptionValues,
			bold = true,
			parent = addInfoBoxElement
		})
	}
	
	-- fill in extra space in uniform arrays
	for i = numAllyTeams * 4 + 1, fragmentShaderMaxTeams * 4, 1 do
		allyTeamColorsVec4Array[i] = 0
	end
	
	--Initialize the ally team colors UBO
	allyTeamColorsUBO = gl.GetVBO(GL.UNIFORM_BUFFER, false)
	allyTeamColorsUBO:Define(1, fragmentShaderMaxTeams)--seconds arg expects size in number of Vec4s
	allyTeamColorsUBO:Upload(allyTeamColorsVec4Array)
	
	myPlayerId = Spring.GetMyPlayerID()
	myAllyTeam = Spring.GetMyAllyTeamID()
	myTeam = Spring.GetMyTeamID()
	myStartBox = startBoxes[myAllyTeam]
	
	--Remove the call-ins that checks for damage if damage in boxes is allowed
	if not noDamageInBoxes then
		widgetHandler.RemoveCallIn(nil, "UnitDamaged")
		widgetHandler.RemoveCallIn(nil, "UnitCommand")
	end
	
	vsx, vsy = Spring.GetViewGeometry()
	widget:ViewResize(vsx, vsy)
	
	--Register the API function used by other widgets to stack boxes in the bottom right corner of the screen
	WG.kingofthehill = {}
	WG.kingofthehill.GetPosition = function()
		if addInfoBoxHidden then
			return {uiBoxPosition.top, uiBoxPosition.left, uiBoxPosition.bottom, uiBoxPosition.right, uiBoxPosition.scale}
		else
			return {addInfoBoxPosition.top, addInfoBoxPosition.left, addInfoBoxPosition.bottom, addInfoBoxPosition.right, addInfoBoxPosition.scale}
		end
	end
	
	activePlayers:add(myPlayerId)--TODO consider moving to dry function
	local newActivePlayerCount = allyTeamActivePlayerCount[myAllyTeam] + 1
	allyTeamActivePlayerCount[myAllyTeam] = newActivePlayerCount
	teamNameAddInfoTexts[myTeam]:setColorOnOff(true)
	
end

-- Gets the position on the screen of the ui box of the widget below our box
-- We make our box the same width as the below box and put it right above
-- Returns top, left, bottom, right, scale
local function getBelowBoxPosition()
	local playerListWG = WG[playerListWidgetName]
	local pos = playerListWG and playerListWG.GetPosition() or {0, vsx, 0, vsx}
	playerListPosition = {top = pos[1], left = pos[2], bottom = pos[3], right = pos[4]}
	
	for _, widgetName in ipairs(belowWidgetsInOrder) do
		local widgetWG = WG[widgetName]
		if widgetWG then
			if not widgetWG.isActive or widgetWG.isActive() then
				if widgetWG.GetPosition then
					local widgetPos = widgetWG.GetPosition()
					if widgetPos then
						return widgetPos
					end
				end
			end
		end
	end
	
	local scale = Spring.GetConfigFloat("ui_scale", 1)
	return {0, floor(vsx-(defaultUIBoxWidth*scale)), 0, vsx, scale}
end

-- Updates uiBoxPosition to the correct value
local function updateUIBoxPosition()
	local belowBoxPos = getBelowBoxPosition()
	local top = ceil(belowBoxPos[1])
	local left = floor(belowBoxPos[2])
	local bottom = floor(belowBoxPos[3])
	local right = ceil(belowBoxPos[4])
	local scale = belowBoxPos[5]
	
	local scaledBoxVerticalPadding = ceil(uiBoxVerticalPadding * scale)
	local scaledBarHeight = ceil(progressBarHeight * scale)
	local scaledBarVerticalSpacing = ceil(progressBarVerticalSpacing * scale)
	local scaledCaptureBarHeight = ceil(captureProgressBarHeight * scale)
	local scaledCaptureBarTopMargin = ceil(captureProgressBarTopMargin * scale)
	local scaledUIBoxHeight = ((scaledBarHeight + scaledBarVerticalSpacing) * numAllyTeams) +
								(2 * scaledBoxVerticalPadding) - scaledBarVerticalSpacing +
								scaledCaptureBarTopMargin + scaledCaptureBarHeight
	
	local teamNameFont = teamNameAddInfoTexts[1].bold and exo2SemiBoldFont or exo2Font
	local modOptionNameFont = modOptionNameAddInfoTexts[1].bold and exo2SemiBoldFont or exo2Font
	local modOptionValueFont = modOptionValueAddInfoTexts[1].bold and exo2SemiBoldFont or exo2Font
	
	local scaledAddInfoTeamTextHeight = ceil(teamNameFont:GetTextHeight("A") * fontSizes.addInfoTeamNames * scale)
	local scaledAddInfoModOptionTextHeight = ceil(max(
		modOptionNameFont:GetTextHeight("A") * fontSizes.addInfoModOptionNames * scale,
		modOptionValueFont:GetTextHeight("A") * fontSizes.addInfoModOptionValues * scale
	))
	local scaledAddInfoTeamVerticalSpacing = ceil(addInfoVerticalSpacing.teamMargin * scale)
	local scaledAddInfoModOptionVerticalSpacing = ceil(addInfoVerticalSpacing.modOptionMargin * scale)
	local scaledAddInfoAllyTeamVerticalSpacing = ceil(addInfoVerticalSpacing.allyTeamMargin * scale)
	local scaledAddInfoSectionVerticalSpacing = ceil(addInfoVerticalSpacing.sectionMargin * scale)
	local scaledAddInfoUIBoxHeight = (scaledAddInfoTeamTextHeight * numTeams) + (scaledAddInfoTeamVerticalSpacing * (numTeams - numAllyTeams)) +
										(scaledAddInfoAllyTeamVerticalSpacing * (numAllyTeams - 1)) +
										scaledAddInfoSectionVerticalSpacing +
										((scaledAddInfoModOptionTextHeight + scaledAddInfoModOptionVerticalSpacing) * 4) -
										scaledAddInfoModOptionVerticalSpacing + (2 * scaledBoxVerticalPadding)
	
	uiBoxPosition = {
		left = left,
		right = right,
		top = top + scaledUIBoxHeight,
		bottom = top,
		width = right - left,
		height = scaledUIBoxHeight,
		scale = scale
	}
	
	addInfoBoxPosition = {
		left = left,
		right = right,
		top = uiBoxPosition.top + scaledAddInfoUIBoxHeight,
		bottom = uiBoxPosition.top,
		width = right - left,
		height = scaledAddInfoUIBoxHeight,
		scale = scale
	}
	
	local absUIBoxHorizontalPadding = uiBoxHorizontalPadding * uiBoxPosition.width
	local absProgressBarWidth = progressBarWidth * uiBoxPosition.width
	local absTimerLeftMargin = timerLeftMargin * uiBoxPosition.width
	
	uiBoxElement:setPos(uiBoxPosition)
	addInfoBoxElement:setPos(addInfoBoxPosition)
	
	local barTopCoord = uiBoxPosition.top - scaledBoxVerticalPadding
	for _, allyTeamId in ipairs(allyTeams) do
		local uiBarPos = {
			top = barTopCoord,
			bottom = barTopCoord - scaledBarHeight,
			left = uiBoxPosition.left + absUIBoxHorizontalPadding,
			right = uiBoxPosition.left + absUIBoxHorizontalPadding + absProgressBarWidth
		}
		allyTeamProgressBars[allyTeamId]:setPos(uiBarPos)
		local progressTimer = allyTeamProgressTimers[allyTeamId]
		progressTimer:setPos({
			top = uiBarPos.top,
			bottom = uiBarPos.bottom,
			left = uiBoxPosition.left + absUIBoxHorizontalPadding + absProgressBarWidth + absTimerLeftMargin,
			right = uiBoxPosition.right - absUIBoxHorizontalPadding
		})
		progressTimer:setFontSize(fontSizes.timers * scale)
		barTopCoord = barTopCoord - scaledBarHeight - scaledBarVerticalSpacing
	end
	
	local captureBarPos = {
		top = barTopCoord + scaledBarVerticalSpacing - scaledCaptureBarTopMargin,
		bottom = uiBoxPosition.bottom + scaledBoxVerticalPadding,
		left = uiBoxPosition.left + absUIBoxHorizontalPadding,
		right = uiBoxPosition.left + absUIBoxHorizontalPadding + absProgressBarWidth
	}
	captureProgressBar:setPos(captureBarPos)
	captureProgressTimer:setPos({
		top = captureBarPos.top,
		bottom = captureBarPos.bottom,
		left = uiBoxPosition.left + absUIBoxHorizontalPadding + absProgressBarWidth + absTimerLeftMargin,
		right = uiBoxPosition.right - absUIBoxHorizontalPadding
	})
	captureProgressTimer:setFontSize(fontSizes.timers * scale)
	
	local textTopCoord = addInfoBoxPosition.top - scaledBoxVerticalPadding
	for _, allyTeamId in ipairs(allyTeams) do
		local allyTeamTeams = allyTeamToTeams:get(allyTeamId)
		for teamId in allyTeamTeams:iter() do
			local teamNameText = teamNameAddInfoTexts[teamId]
			teamNameText:setPos({
				top = textTopCoord,
				bottom = textTopCoord - scaledAddInfoTeamTextHeight,
				left = addInfoBoxPosition.left + absUIBoxHorizontalPadding,
				right = addInfoBoxPosition.right - absUIBoxHorizontalPadding
			})
			teamNameText:setFontSize(fontSizes.addInfoTeamNames * scale)
			textTopCoord = textTopCoord - scaledAddInfoTeamTextHeight - scaledAddInfoTeamVerticalSpacing
		end
		textTopCoord = textTopCoord + scaledAddInfoTeamVerticalSpacing - scaledAddInfoAllyTeamVerticalSpacing
	end
	
	textTopCoord = textTopCoord + scaledAddInfoAllyTeamVerticalSpacing - scaledAddInfoSectionVerticalSpacing
	for i = 1, #modOptionNameAddInfoTexts do
		local nameText = modOptionNameAddInfoTexts[i]
		local valueText = modOptionValueAddInfoTexts[i]
		nameText:setPos({
			top = textTopCoord,
			bottom = textTopCoord - scaledAddInfoModOptionTextHeight,
			left = addInfoBoxPosition.left + absUIBoxHorizontalPadding,
			right = addInfoBoxPosition.left + addInfoBoxPosition.width/2
		})
		valueText:setPos({
			top = textTopCoord,
			bottom = textTopCoord - scaledAddInfoModOptionTextHeight,
			left = addInfoBoxPosition.left + addInfoBoxPosition.width/2,
			right = addInfoBoxPosition.right - absUIBoxHorizontalPadding
		})
		nameText:setFontSize(fontSizes.addInfoModOptionNames * scale)
		valueText:setFontSize(fontSizes.addInfoModOptionValues * scale)
		textTopCoord = textTopCoord - scaledAddInfoModOptionTextHeight - scaledAddInfoModOptionVerticalSpacing
	end
	
end

-- Triggers the UI box position to be updated for the next couple frames.
-- This is used because we don't know the order of the updating of the boxes below ours, so
-- we just update many times.
local function triggerUIBoxResize()
	updateUIBoxPosition()
	screenResizeCountdown = maxScreenResizeCountdown
end

-- Called whenever the window is resized
function widget:ViewResize(vs_x, vs_y)
	vsx = vs_x
	vsy = vs_y
	flowUIDrawElement = WG.FlowUI.Draw.Element
	exo2Font = WG.fonts.getFont(exo2FontPath)
	exo2SemiBoldFont = WG.fonts.getFont(exo2SemiBoldFontPath)
	-- Call here as well as in widget:DrawScreen because I have no idea the order
	-- of other widgets resizing so we want the best chance of getting it right
	triggerUIBoxResize()
end

-- Called upon the start of the game.
function widget:GameStart()
	gameStarted = true
	addInfoBoxHidden = true
	for allyTeamId, numActivePlayers in pairs(allyTeamActivePlayerCount) do
		if numActivePlayers <= 0 then
			allyTeamProgressBars[allyTeamId]:setDisqualified(true)
			allyTeamProgressTimers[allyTeamId]:setDisqualified(true)
		end
	end
	--player list changes size
	triggerUIBoxResize()
end

local timeSinceLastSend = 0
function widget:Update(dt)
	if gameStarted then
		widgetHandler.RemoveCallIn(nil, "Update")
		return
	end
	if timeSinceLastSend < sendInitPacketIntervalSecs then
		timeSinceLastSend = timeSinceLastSend + dt
		return
	end
	VersionInitUIPacket.new():send()
	timeSinceLastSend = 0
end

-- Called whenever a player's status changes e.g. becoming a spectator. Also called when changing teams.
-- Used to queue the player for deactivation, resize the ui box because the player list box below changes
-- size, and update myAllyTeam and myStartBox
function widget:PlayerChanged(playerID)
	if gameStarted then--PlayerChanged is called when a player joins
		playerDeactivationUpdates:put(getNextUpdateFrame(getGameFrame()), playerID)
	end
	triggerUIBoxResize()
	if playerID == myPlayerId then
		myAllyTeam = Spring.GetMyAllyTeamID()
		myTeam = Spring.GetMyTeamID()
		myStartBox = startBoxes[myAllyTeam]
	end
end

-- Called whenever a new player joins the game.
-- Used to send a VersionInitUIPacket whenever a player joins and the game is not yet started.
-- Also resizes the UI box because the player list box below changes size and
-- adds the player to playerToAllyTeam and playerToTeam
function widget:PlayerAdded(playerID)
	local _, _, _, teamId, allyTeamId = Spring.GetPlayerInfo(playerID)
	playerToAllyTeam[playerID] = allyTeamId
	playerToTeam[playerID] = teamId
	triggerUIBoxResize()
end

-- Called whenever a player is removed from the game.
-- Used to queue the player for deactivation and resize the ui box because the player list box below changes size
function widget:PlayerRemoved(playerID, reason)
	
	-- It's unclear whether it would be possible to receive an update from a player after this callin is called, but if it is possible,
	-- we need to make sure the removed player is deactivated on the same frame for everyone, so we simply wait to make sure there are
	-- no more updates from the removed player before we deactivate them
	-- If it is not possible to receive an update from a player after this callin, then we could simply queue a deactivation on the next
	-- update frame after the last received update from the removed player (assuming this callin is called on the same frame for everyone)
	-- TODO figure out which is true
	
	-- Here, we are using the player's lag as a heuristic for how long we should wait before deactivating them
	local gameFrame = getGameFrame()
	local currentPlayerLag = gameFrame - latestReceivedFrames[playerID]
	local waitAmount = max(min(currentPlayerLag, maximumWaitFramesAfterDisconnect), minimumWaitFramesAfterDisconnect)
	removedPlayerDeactivationQueue:put(getNextUpdateFrame(gameFrame + waitAmount), playerID)
	
	triggerUIBoxResize()
end

--Called when a mouse button is pressed. The button parameter supports up to 7 buttons.
--Must return true for MouseRelease and other functions to be called.
--Used to resize our ui box whenever the player list box is clicked since it can change size when certain buttons are clicked.
function widget:MousePress(x, y, button)
	if button ~= 1 then
		return false
	end
	--If inside player list box
	if x <= playerListPosition.right and x >= playerListPosition.left and y >= playerListPosition.bottom and y <= playerListPosition.top then
		triggerUIBoxResize()
	elseif uiBoxElement:isPointInside(x, y) or (not addInfoBoxHidden and addInfoBoxElement:isPointInside(x, y)) then
		addInfoBoxHidden = not addInfoBoxHidden
	end
	return false
end

-- Issues self-destruct commands to all my units and adds them all to selfDestructingUnits
local function destroyAllUnits()
	local myUnits = Set.new()
	myUnits:addAll(Spring.GetTeamUnits(myTeam))
	myUnits:removeAll(selfDestructingUnits)
	Spring.GiveOrderToUnitMap(myUnits.elements, CMD_SELF_DESTRUCT)
end

-- If the modoption is enabled, issues self-destruct commands to all hill buildings and adds all the hill buildings to selfDestructingUnits
local function destroyHillBuildings()
	if not explodeHillUnits then
		return
	end
	local freshHillBuildings = myHillBuildings:clone()
	freshHillBuildings:removeAll(selfDestructingUnits)
	Spring.GiveOrderToUnitMap(freshHillBuildings.elements, CMD_SELF_DESTRUCT)
end

-- Removes the current king if any, adds this stint to his total, and destroys hill buildings if modoption is enabled
local function removeKing(updateFrame)
	local kingTime = allyTeamKingTime[kingAllyTeam] + updateFrame - kingStartFrame
	allyTeamKingTime[kingAllyTeam] = kingTime
	
	local kingProgress = kingTime / winKingTimeFrames
	allyTeamProgressBars[kingAllyTeam]:setProgress(kingProgress)
	allyTeamProgressTimers[kingAllyTeam]:setProgress(kingProgress)
	
	kingAllyTeam = nil
	hillArea:setAllyTeam(nil)
	
	kingWinFrame = math.huge
	kingStartFrame = updateFrame
	
	destroyHillBuildings()
end

-- Resets the capturing timer to zero
local function resetCapturing(updateFrame)
	-- No need to update capture bar team since setting it to nil just uses the first team
	capturingAllyTeam = nil
	-- No need to update capture bar progress since it will be updated in GameFrame
	capturingCompleteFrame = 0
	capturingCountingUp = false
end

-- Removes the player from the set of active players, from the counts of numReceivedPlayers and allyTeamActivePlayerCount,
-- and from playerUpdates for frames after or equal to the given updateFrame and changes the color of their name in the addInfoBox.
-- If the number of active players on this player's ally team is now zero, this function updates their king time according to
-- the given update frame and disqualifies the ally team.
local function deactivatePlayer(playerId, updateFrame)
	
	if not activePlayers:remove(playerId) then
		return
	end
	
	for f = latestReceivedFrames[playerId], updateFrame, -framesPerUpdate do
		playerUpdates:remove(f, playerId)
		numReceivedPlayers[f] = numReceivedPlayers[f] - 1
	end
	
	teamNameAddInfoTexts[playerToTeam[playerId]]:setColorOnOff(false)
	
	local allyTeam = playerToAllyTeam[playerId]
	local newAllyTeamActiveCount = allyTeamActivePlayerCount[allyTeam] - 1
	allyTeamActivePlayerCount[allyTeam] = newAllyTeamActiveCount
	if newAllyTeamActiveCount <= 0 then
		if allyTeam == kingAllyTeam then
			removeKing(updateFrame)
			resetCapturing(updateFrame)
		elseif allyTeam == capturingAllyTeam then
			resetCapturing(updateFrame)
		end
		allyTeamProgressBars[allyTeam]:setDisqualified(true)
		allyTeamProgressTimers[allyTeam]:setDisqualified(true)
	end
	
	addChatLine(updateFrame, getPlayerName(playerId) .. " has been removed from the KOTH session.")
	
end

-- Receives messages from unsynced sent via Spring.SendLuaUIMsg
function widget:RecvLuaMsg(msg, playerId)
	
	if playerId == myPlayerId or (gameStarted and not activePlayers:contains(playerId)) then
		return
	end
	
	local msgLen = #msg
	
	if msgLen == 0 then
		return
	end
	
	local firstChar = substring(msg, 1, 1)
	local notInHill = firstChar == notInHillChar-- only check this first since it is most common
	
	if msgLen == 1 and (notInHill or firstChar == inHillChar) then
		
		local receivedFrame = latestReceivedFrames[playerId] + framesPerUpdate
		latestReceivedFrames[playerId] = receivedFrame
		
		numReceivedPlayers[receivedFrame] = (numReceivedPlayers[receivedFrame] or 0) + 1
		
		playerUpdates:put(receivedFrame, playerId, not notInHill)
		
	elseif msgLen > 2 and firstChar == UIMsgPacket.prefix then
		local packet = UIMsgPacket.deserialize(msg)
		if packet.typeId == DamageInBoxUIPacket.typeId then
			if packet.attackerTeam ~= myTeam then
				return
			end
			Spring.GiveOrderToUnit(packet.attackerUnit, CMD_FIRE_STATE, {FIRE_STATE_HOLD_FIRE})--TODO make sure this works
			damageInBoxUnits:add(packet.attackerUnit)
		elseif packet.typeId == SelfDeactivationUIPacket.typeId then
			playerDeactivationUpdates:put(packet.frame, playerId)
		elseif packet.typeId == VersionInitUIPacket.typeId then
			Spring.Echo("Received Init Packet from: " .. tostring(playerId))
			if gameStarted then
				addChatLine(getGameFrame(), getPlayerName(playerId) .. " tried to join the KOTH session after it started.")
				return
			end
			if packet.version > kothWidgetVersion then
				addChatLine(getGameFrame(), getPlayerName(playerId) .. "'s KOTH widget version (" .. packet.version .. ") is not compatible with yours (" .. kothWidgetVersion .. "). Please update your widget and try again.")
			elseif packet.version < kothWidgetVersion then
				addChatLine(getGameFrame(), getPlayerName(playerId) .. "'s KOTH widget version (" .. packet.version .. ") is not compatible with yours (" .. kothWidgetVersion .. "). Please ask them to update their widget and try again.")
			else
				if activePlayers:add(playerId) then
					local allyTeam = playerToAllyTeam[playerId]
					local newActivePlayerCount = allyTeamActivePlayerCount[allyTeam] + 1
					allyTeamActivePlayerCount[allyTeam] = newActivePlayerCount
					teamNameAddInfoTexts[playerToTeam[playerId]]:setColorOnOff(true)
					addChatLine(getGameFrame(), getPlayerName(playerId) .. " has been added to the KOTH session.")
				end
			end
		else
			log("error", "Unrecognized packet: " .. msg)
		end
	end
	
end

-- A function that updates capturingCompleteFrame when capturingCountingUp is reversed
local function setCapturingCountingUp(value, updateFrame)
	if(value == capturingCountingUp) then
		return
	end
	capturingCountingUp = value
	
	local remainingFrames = max(capturingCompleteFrame - updateFrame, 0)
	capturingCompleteFrame = updateFrame + captureDelayFrames - remainingFrames
end

-- Takes in the next game update (map of players to whether they are in the hill) for the given frame
-- and updates the local game state accordingly
local function processUpdate(update, updateFrame)
	
	-- Get all ally teams that are in the hill to determine if it is being captured
	local allyTeamsInHill = Set.new()
	for playerId, inHill in pairs(update) do
		if inHill then
			allyTeamsInHill:add(playerToAllyTeam[playerId])
		end
	end
	
	-- End the game if the king won
	if updateFrame >= kingWinFrame and kingAllyTeam ~= myAllyTeam then
		destroyAllUnits()
		--TODO consider blocking all commands or doing something else like that
	end
	
	-- Capture the hill if the captureDelay has elapsed
	if updateFrame >= capturingCompleteFrame then
		if kingAllyTeam and not capturingCountingUp then
			removeKing(updateFrame)
		elseif not kingAllyTeam and capturingCountingUp then
			-- Set the new king and the king starting/win frame
			kingAllyTeam = capturingAllyTeam
			kingStartFrame = updateFrame
			kingWinFrame = updateFrame + winKingTimeFrames - allyTeamKingTime[kingAllyTeam]
			hillArea:setAllyTeam(kingAllyTeam)
		end
	end
	
	-- Logic to determine if hill is being captured
	if kingAllyTeam then
		if allyTeamsInHill:contains(kingAllyTeam) and (kingKeepsHill or allyTeamsInHill.size == 1) then
			setCapturingCountingUp(true, updateFrame)
		else
			setCapturingCountingUp(false, updateFrame)
		end
	else
		if allyTeamsInHill.size == 1 and (updateFrame >= capturingCompleteFrame or allyTeamsInHill:contains(capturingAllyTeam)) then
			setCapturingCountingUp(true, updateFrame)
			capturingAllyTeam = allyTeamsInHill:unpack()
			captureProgressBar:setAllyTeam(capturingAllyTeam)
		else
			setCapturingCountingUp(false, updateFrame)
		end
	end
	
end

local updateCounter = 0
-- Called for every game simulation frame
-- Processes the next update if we have received updates from all players. If an update was processed,
-- the UI elements are updated accordingly.
function widget:GameFrame(frame)-- Note: first frame = 0
	lastGameFrame = frame
	updateCounter = updateCounter - 1
	if updateCounter > 0 then
		return
	end
	updateCounter = framesPerUpdate
	
	if activePlayers:contains(myPlayerId) then
		local inHill = false
		for unitId in myCaptureQualifiedUnits:iter() do
			local unitX, _, unitZ = Spring.GetUnitPosition(unitId)
			if hillArea:isPointInside(unitX, unitZ) then
				inHill = true
				break
			end
		end
		
		playerUpdates:put(frame, myPlayerId, inHill)
		Spring.SendLuaUIMsg(inHill and inHillChar or notInHillChar)
		latestReceivedFrames[myPlayerId] = frame
		numReceivedPlayers[frame] = (numReceivedPlayers[frame] or 0) + 1
	end
	
	local updateProcessed = false
	
	local updateFrame = currentStateFrame + framesPerUpdate
	
	-- This uses the game frame not the update frame (see removedPlayerDeactivationQueue and PlayerRemoved)
	if removedPlayerDeactivationQueue:containsKey(frame) then
		for playerId in removedPlayerDeactivationQueue:get(frame):iter() do
			deactivatePlayer(playerId, updateFrame)-- this should be updateFrame, not frame
		end
		removedPlayerDeactivationQueue:removeAll(frame)
	end
	
	while true do
		
		-- We must process deactivations before we check if we have received updates from all players
		if playerDeactivationUpdates:containsKey(updateFrame) then
			for playerId in playerDeactivationUpdates:get(updateFrame):iter() do
				deactivatePlayer(playerId, updateFrame)
			end
			playerDeactivationUpdates:removeAll(updateFrame)
		end
		
		local receivedPlayersForUpdate = numReceivedPlayers[updateFrame]
		if not receivedPlayersForUpdate or receivedPlayersForUpdate < activePlayers.size then
			break
		end
		
		processUpdate(playerUpdates:getAll(updateFrame), updateFrame)
		
		playerUpdates:removeAll(updateFrame)
		numReceivedPlayers[updateFrame] = nil
		
		currentStateFrame = updateFrame
		updateFrame = updateFrame + framesPerUpdate
		updateProcessed = true
		
	end
	
	if not updateProcessed then
		return
	end
	
	if kingAllyTeam then
		local kingProgress = (allyTeamKingTime[kingAllyTeam] + (currentStateFrame - kingStartFrame)) / winKingTimeFrames
		allyTeamProgressBars[kingAllyTeam]:setProgress(kingProgress)--fine
		allyTeamProgressTimers[kingAllyTeam]:setProgress(kingProgress)--fine
	end
	
	local captureProgress = (capturingCompleteFrame - currentStateFrame) / captureDelayFrames
	if capturingCountingUp then
		captureProgress = 1 - captureProgress
	end
	captureProgressBar:setProgress(captureProgress)--fine
	captureProgressTimer:setProgress(captureProgress)--fine
end

--Called when a team dies. Used to queue an update to deactivate the players on the team.
--We also resize the ui box because removing a team changes the sizes of the lower boxes.
function widget:TeamDied(teamID)
	playerDeactivationUpdates:putAll(getNextUpdateFrame(getGameFrame()), Spring.GetPlayerList(teamID))
	triggerUIBoxResize()
end

function widget:UnsyncedHeightMapUpdate(x1, z1, x2, z2)--TODO consider using height texture in vertex shader
	x1, z1, x2, z2 = x1 * squareSize, z1 * squareSize, x2 * squareSize, z2 * squareSize
	
	if shouldDrawStartBoxes then
		for _, startArea in pairs(startBoxes) do
			if startArea:isRectIntersectingOutline(x1, z1, x2, z2) then
				startArea:invalidatePosition()
			end
		end
	end
	
	if hillArea:isRectIntersectingOutline(x1, z1, x2, z2) then
		hillArea:invalidatePosition()
	end
end

-- No documentation. This is the call-in that many other widgets use to draw UI.
function widget:DrawScreen()
	
	if screenResizeCountdown > 0 then
		-- Update the UI box position multiple times because I have no idea the order
		-- of other widgets resizing so we want the best chance of getting it right
		updateUIBoxPosition()
		screenResizeCountdown = screenResizeCountdown - 1
	end
	
	gl.DepthTest(false)
	gl.DepthMask(false)
	
	uiBoxElement:drawFrame()
	
	for _, uiTextTimer in pairs(allyTeamProgressTimers) do
		uiTextTimer:drawFrame()
	end
	
	captureProgressTimer:drawFrame()
	
	for _, uiBar in pairs(allyTeamProgressBars) do
		uiBar:drawFrame()
	end
	
	captureProgressBar:drawFrame()
	
	unbindAllyTeamColorsUBO()
	useShader(0)
	
	if not addInfoBoxHidden then
		
		addInfoBoxElement:drawFrame()
		
		for _, nameText in pairs(teamNameAddInfoTexts) do
			nameText:drawFrame()
		end
		
		for i = 1, #modOptionNameAddInfoTexts do
			modOptionNameAddInfoTexts[i]:drawFrame()
			modOptionValueAddInfoTexts[i]:drawFrame()
		end
		
	end
	
end

function widget:DrawWorldPreUnit()
	
	gl.DepthTest(GL.LEQUAL)
	gl.DepthMask(false)
	
	if shouldDrawStartBoxes then
		for _, mapArea in pairs(startBoxes) do
			mapArea:drawFrame()
		end
	end
	
	hillArea:drawFrame()
	
	resetLineWidth()
	unbindAllyTeamColorsUBO()
	useShader(0)
	
end

--Called when a unit is transferred between teams. Used to keep track of myCaptureQualifiedUnits
function widget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
	if not captureQualifiedUnitDefIds:contains(unitDefID) then
		return
	end
	if newTeam == myTeam then
		myCaptureQualifiedUnits:add(unitID)
	elseif oldTeam == myTeam then
		myCaptureQualifiedUnits:remove(unitID)
	end
end

--Called at the moment the unit is completed [constructed]. Used to start tracking capture-qualified units.
--Start tracking capture qualified units here instead of in UnitCreated so that only fully constructed units can capture the hill.
function widget:UnitFinished(unitID, unitDefID, unitTeam)
	if unitTeam ~= myTeam or not captureQualifiedUnitDefIds:contains(unitDefID) then
		return
	end
	myCaptureQualifiedUnits:add(unitID)
end

--Called when a unit is destroyed. Used to stop tracking capture-qualified units and buildings in the hill and start box
function widget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
	if unitTeam ~= myTeam then
		return
	end
	myCaptureQualifiedUnits:remove(unitID)
	myHillBuildings:remove(unitID)
	myStartBoxBuildings:remove(unitID)
end

--Called at the moment the unit is created.
--Used to track buildings inside the hill to be blown up upon transfer of the throne
function widget:UnitCreated(unitID, unitDefID, unitTeam, builderID)
	if unitTeam ~= myTeam then
		return
	end
	local unitDef = UnitDefs[unitDefID]
	if unitDef.isBuilding or unitDef.isStaticBuilder then
		local rotation = Spring.GetUnitBuildFacing(unitID)
		-- rotation 0=south(-z), 1=east(+x), 2=north(+z), 3=west(-x), unitDef sizeX and sizeZ seem to refer to north/south orientation
		local sizeX = (rotation % 2 == 0 and unitDef.xsize or unitDef.zsize) * squareSize
		local sizeZ = (rotation % 2 == 0 and unitDef.zsize or unitDef.xsize) * squareSize
		local unitX, _, unitZ = Spring.GetUnitPosition(unitID)
		if hillArea:isBuildingOverlapping(unitX, unitZ, sizeX, sizeZ) then
			myHillBuildings:add(unitID)
		end
		if myStartBox:isBuildingInside(unitX, unitZ, sizeX, sizeZ) then
			myStartBoxBuildings:add(unitID)
		end
	end
end

-- Called when a command is issued. Returning true deletes the command and does not send it through the network.
-- Used to block build commands that are outside of permitted areas and to block any commands that are inside
-- another team's start box
function widget:CommandNotify(cmdID, cmdParams, cmdOptions)
	if cmdID == CMD_MOVE or cmdID == CMD_PATROL or cmdID == CMD_FIGHT then
		local x, _, z = table.unpack(cmdParams)
		for allyTeamId, startBox in pairs(startBoxes) do
			if allyTeamId ~= myAllyTeam and startBox:isPointInside(x, z) then
				return true
			end
		end
	elseif cmdID == CMD_ATTACK or cmdID == CMD_SET_TARGET then
		local x, z, r
		if #cmdParams == 1 then
			local targetUnit = cmdParams[1]
			x, _, z = Spring.GetUnitPosition(targetUnit)
			r = 0
		else
			x, _, z, r = table.unpack(cmdParams)
		end
		for allyTeamId, startBox in pairs(startBoxes) do
			if allyTeamId ~= myAllyTeam and startBox:isCircleOverlapping(x, z, r) then
				return true
			end
		end
	elseif cmdID == CMD_SELF_DESTRUCT then
		if selfDestructingUnits:containsAny(Spring.GetSelectedUnits()) then
			return true
		end
	end
	
	local buildingUnitDef = UnitDefs[-cmdID]
	if buildingUnitDef and (buildingUnitDef.isBuilding or buildingUnitDef.isStaticBuilder) then
		local cmdX, _, cmdZ, rotation = table.unpack(cmdParams)
		-- rotation 0=south(-z), 1=east(+x), 2=north(+z), 3=west(-x), unitDef sizeX and sizeZ seem to refer to north/south orientation
		local sizeX = (rotation % 2 == 0 and buildingUnitDef.xsize or buildingUnitDef.zsize) * squareSize
		local sizeZ = (rotation % 2 == 0 and buildingUnitDef.zsize or buildingUnitDef.xsize) * squareSize
		
		if buildOutsideBoxes then
			for allyTeamId, startBox in pairs(startBoxes) do
				if allyTeamId ~= myAllyTeam and startBox:isBuildingInside(cmdX, cmdZ, sizeX, sizeZ) then
					return true
				end
			end
			if hillBuildRule == 1 or (hillBuildRule == 2 and myAllyTeam ~= kingAllyTeam) then
				if hillArea:isBuildingInside(cmdX, cmdZ, sizeX, sizeZ) then
					return true
				end
			end
			return false
		else
			if myStartBox:isBuildingInside(cmdX, cmdZ, sizeX, sizeZ) then
				return false
			end
			if hillBuildRule == 3 or (hillBuildRule == 2 and myAllyTeam == kingAllyTeam) then
				if hillArea:isBuildingInside(cmdX, cmdZ, sizeX, sizeZ) then
					return false
				end
			end
			return true
		end
	end
end

-- Called by cmd_customformations2.lua when a formation command is issued
function widget:UnitCommandNotify(unitID, cmdID, cmdParams, cmdOptions)
	return widget:CommandNotify(cmdID, cmdParams, cmdOptions)
end

-- Called after a unit accepts a command. Used for fire state commands because they don't get passed into CommandNotify
function widget:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag)
	-- cmdID seems to only equal CMD_FIRE_STATE when switching to 'return fire' or 'fire at will'
	if cmdID ~= CMD_FIRE_STATE or unitTeam ~= myTeam or not damageInBoxUnits:contains(unitID) then
		return
	end
	local unitX, _, unitZ = Spring.GetUnitPosition(unitID)
	for allyTeamId, startBox in pairs(startBoxes) do
		if allyTeamId ~= myAllyTeam and startBox:isPointInside(unitX, unitZ) then
			Spring.GiveOrderToUnit(unitID, CMD_FIRE_STATE, {FIRE_STATE_HOLD_FIRE})--TODO make sure this works
			return
		end
	end
	damageInBoxUnits:remove(unitID)
end

-- Called when a unit is damaged. Used to detect if units in hill are being damaged when noDamageInBoxes is true
local lastCheckedFrame = -math.huge
function widget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
	if not noDamageInBoxes then--TODO remove this if it works
		log("error", "Call-in was not removed!!! (UnitDamaged)")
		return
	end
	if lastGameFrame - lastCheckedFrame < minFramesBetweenDamageCheck then
		return
	end
	if unitTeam == myTeam and teamToAllyTeam[attackerTeam] ~= myAllyTeam then
		lastCheckedFrame = lastGameFrame
		local unitX, _, unitZ = Spring.GetUnitPosition(unitID)
		if myStartBox:isPointInside(unitX, unitZ) then
			local packet = DamageInBoxUIPacket.new({attackerTeam = attackerTeam, attackerUnit = attackerID})
			packet:send()
			packet:queueUpdate()
		end
	end
end

function widget:Shutdown()
	
	gl.DeleteShader(progressBarShader)
	gl.DeleteShader(mapAreaShader)
	
	WG.kingofthehill = nil
	
	destroyHillBuildings()
	
	SelfDeactivationUIPacket.new({frame = getNextUpdateFrame(latestReceivedFrames[myPlayerId] or -framesPerUpdate)}):send()
	
end