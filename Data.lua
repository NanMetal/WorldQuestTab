local addonName, addon = ...

addon.WQT = LibStub("AceAddon-3.0"):NewAddon("WorldQuestTab");
addon.externals = {};
addon.variables = {};
addon.debug = false;
addon.setupPhase = true;
addon.WQT_Utils = {};
local WQT_Utils = addon.WQT_Utils;
local WQT_Profiles = addon.WQT_Profiles;
local _L = addon.L;
local _V = addon.variables;
local WQT = addon.WQT;
local _emptyTable = {};
local _playerFaction = UnitFactionGroup("Player");

--------------------------------
-- Custom Event mixin
--------------------------------

WQT_CallbackMixin = {};

function WQT_CallbackMixin:RegisterCallback(event, func)
	-- Find the source calling the function
	local debugLine = debugstack(2, 1, 1);
	local source = string.match(debugLine, "Interface\\AddOns\\(%a+)\\") or "Unknown";

	if (not self.callbacks) then
		self.callbacks = {};
	end

	local callback = self.callbacks[event];
	if (not callback) then 
		callback = {};
		self.callbacks[event] = callback;
	end
	
	tinsert(callback, {["func"] = func, ["source"] = source});
end

function WQT_CallbackMixin:TriggerCallback(event, ...)
	if (not self.callbacks or not self.callbacks[event]) then
		return;
	end
	
	for k, callback in ipairs(self.callbacks[event]) do
		callback.func(...);
	end
end

-- Hook Micin
WQT_EventHookMixin = {};

function WQT_EventHookMixin:HookEvent(event, func)
	-- Find the source calling the function
	local debugLine = debugstack(2, 1, 1);
	local source = string.match(debugLine, "Interface\\AddOns\\(%a+)\\") or "Unknown";

	if (not self.eventHooks) then
		self.eventHooks = {};
	end

	local callback = self.eventHooks[event];
	if (not callback) then 
		callback = {};
		self.eventHooks[event] = callback;
	end

	tinsert(callback, {["func"] = func, ["source"] = source});
end

function WQT_EventHookMixin:OnEvent(event, ...)
	if (not self.eventHooks or not self.eventHooks[event]) then
		return;
	end
	
	for k, callback in ipairs(self.eventHooks[event]) do
		callback.func(event, ...);
	end
end



addon.WQT_Profiles =  CreateFromMixins(WQT_CallbackMixin);
local WQT_Profiles = addon.WQT_Profiles;



------------------------
-- PUBLIC
------------------------

WQT_REWARDTYPE = {
	["none"] = 			0,		--0
	["weapon"] = 		2^0,	--1
	["equipment"] =		2^1,	--2
	["conduit"] = 		2^2,	--4
	["relic"] = 			2^3,	--8
	["anima"] = 			2^4,	--16
	["artifact"] = 		2^5,	--32
	["spell"] = 			2^6,	--64
	["item"] = 			2^7,	--128
	["gold"] = 			2^8,	--256
	["currency"] = 		2^9,	--512
	["honor"] = 			2^10,	--1024
	["reputation"] =		2^11,	--2048
	["xp"] = 			2^12,	--4096
	["missing"] = 		2^13,	--8192
	
};

WQT_QUESTTYPE = {
	["normal"] = 	0,
	["daily"] = 		2^0,	--1
	["threat"] =		2^1,	--2
	["calling"] = 	2^2,	--4
	["bonus"] = 		2^3,	--8
	["combatAlly"] =	2^4,	--16
}

_V["CONDUIT_SUBTYPE"] = {
	["endurance"] = 1,
	["finesse"] = 2,
	["potency"] = 3,
}

-- Combos
WQT_REWARDTYPE.gear = bit.bor(WQT_REWARDTYPE.weapon, WQT_REWARDTYPE.equipment);

WQT_GROUP_INFO = _L["GROUP_SEARCH_INFO"];
WQT_CONTAINER_DRAG = _L["CONTAINER_DRAG"];
WQT_CONTAINER_DRAG_TT = _L["CONTAINER_DRAG_TT"];
WQT_FULLSCREEN_BUTTON_TT = _L["WQT_FULLSCREEN_BUTTON_TT"];

------------------------
-- LOCAL
------------------------

local function _DeepWipeTable(t)
	for k, v in pairs(t) do
		if (type(v) == "table") then
			_DeepWipeTable(v)
		end
	end
	wipe(t);
	t = nil;
end
-- /dump WorldMapFrame:GetMapID()
local WQT_WAR_WITHIN = {
	[2214] =  {["x"] = 0.57, ["y"] = 0.59}, -- The Ringing Deeps
	[2215] =  {["x"] = 0.37, ["y"] = 0.48}, -- Hallowfall
	[2248] =  {["x"] = 0.76, ["y"] = 0.21}, -- Isle of Dorn
	[2255] =  {["x"] = 0.46, ["y"] = 0.69}, -- Azj-Kahet
	-- [2256] =  {["x"] = 0.46, ["y"] = 0.69}, -- Azj-Kahet - Lower
	[2213] =  {["x"] = 0.44, ["y"] = 0.73}, -- City of Threads
	-- [2216] =  {["x"] = 0.44, ["y"] = 0.73}, -- City of Threads - Lower
	[2339] =  {["x"] = 0.73, ["y"] = 0.25}, -- Dornogal
	-- For some reason the Siren Isle is inside the Isle of Dorn map...
	[2369] =  {["x"] = 0.76, ["y"] = 0.21}, -- Siren Isle
}
local WQT_DRAGONFLIGHT = {
	[2026] =  {["x"] = 0.66, ["y"] = 0.09}, -- Forbidden Reach (dracthyr start)
	[2151] =  {["x"] = 0.66, ["y"] = 0.09}, -- Forbidden Reach
	[2112] =  {["x"] = 0.55, ["y"] = 0.48}, -- Valdrakken
	[2022] =  {["x"] = 0.49, ["y"] = 0.35}, -- Waking Shores
	[2023] =  {["x"] = 0.42, ["y"] = 0.56}, -- Ohn'ahran Plains
	[2024] =  {["x"] = 0.53, ["y"] = 0.74}, -- Azure Span
	[2025] =  {["x"] = 0.63, ["y"] = 0.50}, -- Thaldraszus
	[2085] =  {["x"] = 0.66, ["y"] = 0.57}, -- Primalist Future
	[2133] =  {["x"] = 0.86, ["y"] = 0.83}, -- Zaralek Cavern
	[2200] =  {["x"] = 0.31, ["y"] = 0.55}, -- Emerald Dream
}
local WQT_SHADOWLANDS = {
	[1543] =  {["x"] = 0.23, ["y"] = 0.13}, -- The Maw
	[1536] = {["x"] = 0.62, ["y"] = 0.21}, -- Maldraxxus
	[1525] = {["x"] = 0.24, ["y"] = 0.54}, -- Revendreth
	[1670] = {["x"] = 0.47, ["y"] = 0.51}, -- Oribos
	[1533] = {["x"] = 0.71, ["y"] = 0.57}, -- Bastion
	[1565] = {["x"] = 0.48, ["y"] = 0.80}, -- Ardenweald
	[1961] = {["x"] = 0.30, ["y"] = 0.25}, -- Korthia
	[1970] = {["x"] = 0.85, ["y"] = 0.80}, -- Zereth Mortis
}
local WQT_ZANDALAR = {
	[864] =  {["x"] = 0.39, ["y"] = 0.32}, -- Vol'dun
	[863] = {["x"] = 0.57, ["y"] = 0.28}, -- Nazmir
	[862] = {["x"] = 0.55, ["y"] = 0.61}, -- Zuldazar
	[1165] = {["x"] = 0.55, ["y"] = 0.61}, -- Dazar'alor
	[1355] = {["x"] = 0.86, ["y"] = 0.14}, -- Nazjatar
}
local WQT_KULTIRAS = {
	[942] =  {["x"] = 0.55, ["y"] = 0.25}, -- Stromsong Valley
	[896] = {["x"] = 0.36, ["y"] = 0.67}, -- Drustvar
	[895] = {["x"] = 0.56, ["y"] = 0.54}, -- Tiragarde Sound
	[1161] = {["x"] = 0.56, ["y"] = 0.54}, -- Boralus
	[1169] = {["x"] = 0.78, ["y"] = 0.61}, -- Tol Dagor
	[1355] = {["x"] = 0.86, ["y"] = 0.14}, -- Nazjatar
	[1462] = {["x"] = 0.17, ["y"] = 0.28}, -- Mechagon
}
local WQT_LEGION_ARGUS = {
	[830]	= {["x"] = 0.49, ["y"] = 0.29}, -- Krokuun
	[885]	= {["x"] = 0.29, ["y"] = 0.71}, -- Antoran Wastes
	[882]	= {["x"] = 0.80, ["y"] = 0.71}, -- Mac'Aree
}
local WQT_LEGION = {
	[630]	= {["x"] = 0.33, ["y"] = 0.58}, -- Azsuna
	[680]	= {["x"] = 0.46, ["y"] = 0.45}, -- Suramar
	[634]	= {["x"] = 0.60, ["y"] = 0.33}, -- Stormheim
	[650]	= {["x"] = 0.46, ["y"] = 0.23}, -- Highmountain
	[641]	= {["x"] = 0.34, ["y"] = 0.33}, -- Val'sharah
	[790]	= {["x"] = 0.46, ["y"] = 0.84}, -- Eye of Azshara
	[646]	= {["x"] = 0.54, ["y"] = 0.68}, -- Broken Shore
	[627]	= {["x"] = 0.45, ["y"] = 0.64}, -- Dalaran
	[905] 	= {["x"] = 0.86, ["y"] = 0.17}, -- Argus
}
local WQT_KALIMDOR = { 
	[81] 	= {["x"] = 0.42, ["y"] = 0.82}, -- Silithus
	[64]	= {["x"] = 0.5, ["y"] = 0.72}, -- Thousand Needles
	[249]	= {["x"] = 0.47, ["y"] = 0.91}, -- Uldum
	[1527]	= {["x"] = 0.47, ["y"] = 0.91}, -- Uldum BfA
	[71]	= {["x"] = 0.55, ["y"] = 0.84}, -- Tanaris
	[78]	= {["x"] = 0.5, ["y"] = 0.81}, -- Ungoro
	[69]	= {["x"] = 0.43, ["y"] = 0.7}, -- Feralas
	[70]	= {["x"] = 0.55, ["y"] = 0.67}, -- Dustwallow
	[199]	= {["x"] = 0.51, ["y"] = 0.67}, -- S Barrens
	[7]		= {["x"] = 0.47, ["y"] = 0.6}, -- Mulgore
	[66]	= {["x"] = 0.41, ["y"] = 0.57}, -- Desolace
	[65]	= {["x"] = 0.43, ["y"] = 0.46}, -- Stonetalon
	[10]	= {["x"] = 0.52, ["y"] = 0.5}, -- N Barrens
	[1]		= {["x"] = 0.58, ["y"] = 0.5}, -- Durotar
	[63]	= {["x"] = 0.49, ["y"] = 0.41}, -- Ashenvale
	[62]	= {["x"] = 0.46, ["y"] = 0.23}, -- Dakshore
	[76]	= {["x"] = 0.59, ["y"] = 0.37}, -- Azshara
	[198]	= {["x"] = 0.54, ["y"] = 0.32}, -- Hyjal
	[77]	= {["x"] = 0.49, ["y"] = 0.25}, -- Felwood
	[80]	= {["x"] = 0.53, ["y"] = 0.19}, -- Moonglade
	[83]	= {["x"] = 0.58, ["y"] = 0.23}, -- Winterspring
	[57]	= {["x"] = 0.42, ["y"] = 0.1}, -- Teldrassil
	[97]	= {["x"] = 0.33, ["y"] = 0.27}, -- Azuremyst
	[106]	= {["x"] = 0.3, ["y"] = 0.18}, -- Bloodmyst
}
local WQT_EASTERN_KINGDOMS = {
	[210]	= {["x"] = 0.47, ["y"] = 0.87}, -- Cape of STV
	[50]	= {["x"] = 0.47, ["y"] = 0.87}, -- N STV
	[17]	= {["x"] = 0.54, ["y"] = 0.89}, -- Blasted Lands
	[51]	= {["x"] = 0.54, ["y"] = 0.78}, -- Swamp of Sorrow
	[42]	= {["x"] = 0.49, ["y"] = 0.79}, -- Deadwind
	[47]	= {["x"] = 0.45, ["y"] = 0.8}, -- Duskwood
	[52]	= {["x"] = 0.4, ["y"] = 0.79}, -- Westfall
	[37]	= {["x"] = 0.47, ["y"] = 0.75}, -- Elwynn
	[49]	= {["x"] = 0.51, ["y"] = 0.75}, -- Redridge
	[36]	= {["x"] = 0.49, ["y"] = 0.7}, -- Burning Steppes
	[32]	= {["x"] = 0.47, ["y"] = 0.65}, -- Searing Gorge
	[15]	= {["x"] = 0.52, ["y"] = 0.65}, -- Badlands
	[27]	= {["x"] = 0.44, ["y"] = 0.61}, -- Dun Morogh
	[48]	= {["x"] = 0.52, ["y"] = 0.6}, -- Loch Modan
	[241]	= {["x"] = 0.56, ["y"] = 0.55}, -- Twilight Highlands
	[56]	= {["x"] = 0.5, ["y"] = 0.53}, -- Wetlands
	[14]	= {["x"] = 0.51, ["y"] = 0.46}, -- Arathi Highlands
	[26]	= {["x"] = 0.57, ["y"] = 0.4}, -- Hinterlands
	[25]	= {["x"] = 0.46, ["y"] = 0.4}, -- Hillsbrad
	[217]	= {["x"] = 0.4, ["y"] = 0.48}, -- Ruins of Gilneas
	[21]	= {["x"] = 0.41, ["y"] = 0.39}, -- Silverpine
	[18]	= {["x"] = 0.39, ["y"] = 0.32}, -- Tirisfall
	[22]	= {["x"] = 0.49, ["y"] = 0.31}, -- W Plaugelands
	[23]	= {["x"] = 0.54, ["y"] = 0.32}, -- E Plaguelands
	[95]	= {["x"] = 0.56, ["y"] = 0.23}, -- Ghostlands
	[94]	= {["x"] = 0.54, ["y"] = 0.18}, -- Eversong
	[122]	= {["x"] = 0.55, ["y"] = 0.05}, -- Quel'Danas
}
local WQT_OUTLAND = {
	[104]	= {["x"] = 0.74, ["y"] = 0.8}, -- Shadowmoon Valley
	[108]	= {["x"] = 0.45, ["y"] = 0.77}, -- Terrokar
	[107]	= {["x"] = 0.3, ["y"] = 0.65}, -- Nagrand
	[100]	= {["x"] = 0.52, ["y"] = 0.51}, -- Hellfire
	[102]	= {["x"] = 0.33, ["y"] = 0.47}, -- Zangarmarsh
	[105]	= {["x"] = 0.36, ["y"] = 0.23}, -- Blade's Edge
	[109]	= {["x"] = 0.57, ["y"] = 0.2}, -- Netherstorm
}
local WQT_NORTHREND = {
	[114]	= {["x"] = 0.22, ["y"] = 0.59}, -- Borean Tundra
	[119]	= {["x"] = 0.25, ["y"] = 0.41}, -- Sholazar Basin
	[118]	= {["x"] = 0.41, ["y"] = 0.26}, -- Icecrown
	[127]	= {["x"] = 0.47, ["y"] = 0.55}, -- Crystalsong
	[120]	= {["x"] = 0.61, ["y"] = 0.21}, -- Stormpeaks
	[121]	= {["x"] = 0.77, ["y"] = 0.32}, -- Zul'Drak
	[116]	= {["x"] = 0.71, ["y"] = 0.53}, -- Grizzly Hillsbrad
	[113]	= {["x"] = 0.78, ["y"] = 0.74}, -- Howling Fjord
}
local WQT_PANDARIA = {
	[554]	= {["x"] = 0.9, ["y"] = 0.68}, -- Timeless Isles
	[371]	= {["x"] = 0.67, ["y"] = 0.52}, -- Jade Forest
	[418]	= {["x"] = 0.53, ["y"] = 0.75}, -- Karasang
	[376]	= {["x"] = 0.51, ["y"] = 0.65}, -- Four Winds
	[422]	= {["x"] = 0.35, ["y"] = 0.62}, -- Dread Waste
	[390]	= {["x"] = 0.5, ["y"] = 0.52}, -- Eternal Blossom
	[379]	= {["x"] = 0.45, ["y"] = 0.35}, -- Kun-lai Summit
	[507]	= {["x"] = 0.48, ["y"] = 0.05}, -- Isle of Giants
	[388]	= {["x"] = 0.32, ["y"] = 0.45}, -- Townlong Steppes
	[504]	= {["x"] = 0.2, ["y"] = 0.11}, -- Isle of Thunder
	[1530]	= {["x"] = 0.51, ["y"] = 0.53}, -- Vale Of Eternal Blossom BfA
}
local WQT_DRAENOR = {
	[550]	= {["x"] = 0.24, ["y"] = 0.49}, -- Nagrand
	[525]	= {["x"] = 0.34, ["y"] = 0.29}, -- Frostridge
	[543]	= {["x"] = 0.49, ["y"] = 0.21}, -- Gorgrond
	[535]	= {["x"] = 0.43, ["y"] = 0.56}, -- Talador
	[542]	= {["x"] = 0.46, ["y"] = 0.73}, -- Spired of Arak
	[539]	= {["x"] = 0.58, ["y"] = 0.67}, -- Shadowmoon
	[534]	= {["x"] = 0.58, ["y"] = 0.47}, -- Tanaan Jungle
	[558]	= {["x"] = 0.73, ["y"] = 0.43}, -- Ashran
}

local ZonesByExpansion = {
	[LE_EXPANSION_WAR_WITHIN] = {
		2274, -- Khaz Algar
		2214, -- The Ringing Deeps
		2215, -- Hallowfall
		2248, -- Isle of Dorn
		2255, -- Azj-Kahet
		2256, -- Azj-Kahet - Lower
		2369, -- Siren Isle
	}
	,[LE_EXPANSION_DRAGONFLIGHT] = {
		1978, -- Dragon Isles
		2026, -- Forbidden Reach (dracthyr start)
		2151, -- Forbidden Reach
		2112, -- Valdrakken
		2022, -- Waking Shores
		2023, -- Ohn'ahran Plains
		2024, -- Azure Span
		2025, -- Thaldraszus
		2085, -- Primalist Future
		2133, -- Zaralek Cavern
		2200, -- Emerald Dream
	}
	,[LE_EXPANSION_SHADOWLANDS] = {
		1550, -- The Shadowlands
		1543, -- The Maw
		1536, -- Maldraxxus
		1525, -- Revendreth
		1670, -- Oribos
		1533, -- Bastion
		1565, -- Ardenweald
		1701, -- Ardenweald covenant
		1702, -- Ardenweald covenant
		1703, -- Ardenweald covenant
		1707, -- Bastion Covenant
		1708, -- Bastion Covenant
		1699, -- Revendreth Covenant
		1700, -- Revendreth Covenant
		1698, -- Maldraxxus Covenant
		1961, -- Korthia
		1970, -- Zereth Mortis
	}
	,[LE_EXPANSION_BATTLE_FOR_AZEROTH] = {
		875, -- Zandalar
		864, -- Vol'dun
		863, -- Nazmir
		862, -- Zuldazar
		1165, -- Dazar'alor
		876, -- Kul Tiras
		942, -- Stromsong Valley
		896, -- Drustvar
		895, -- Tiragarde Sound
		1161, -- Boralus
		1169, -- Tol Dagor
		1355, -- Nazjatar
		1462, -- Mechagon
		--Classic zones with BfA WQ
		14, -- Arathi Highlands
		62, -- Darkshore
		1527, -- Uldum
		1530, -- Vale of Eternam Blossom
		
	}
	,[LE_EXPANSION_LEGION] = {
		619, -- Broken Isles
		630, -- Azsuna
		680, -- Suramar
		634, -- Stormheim
		650, -- Highmountain
		641, -- Val'sharah
		790, -- Eye of Azshara
		646, -- Broken Shore
		627, -- Dalaran
		830, -- Krokuun
		885, -- Antoran Wastes
		882, -- Mac'Aree
		905, -- Argus
	}
	,[LE_EXPANSION_WARLORDS_OF_DRAENOR] = {
		572, -- Draenor
		525, -- Frostfire Ridge
		543, -- Gorgrond
		534, -- Tanaan Jungle
		535, -- Talador
		550, -- Nagrand
		542, -- Spires of Arak
		588, -- Ashran
	}
}

-- A list of every zones linked to an expansion level
_V["WQT_ZONE_EXPANSIONS"] = {}


local function AddZonesToList(t)
	for mapID, v in pairs(t) do
		_V["WQT_ZONE_EXPANSIONS"][mapID] = 0;
	end
end

AddZonesToList(WQT_WAR_WITHIN);
AddZonesToList(WQT_DRAGONFLIGHT);
AddZonesToList(WQT_SHADOWLANDS);
AddZonesToList(WQT_ZANDALAR);
AddZonesToList(WQT_KULTIRAS);
AddZonesToList(WQT_LEGION_ARGUS);
AddZonesToList(WQT_LEGION);
AddZonesToList(WQT_KALIMDOR);
AddZonesToList(WQT_EASTERN_KINGDOMS);
AddZonesToList(WQT_DRAENOR);
AddZonesToList(WQT_PANDARIA);
AddZonesToList(WQT_NORTHREND);
AddZonesToList(WQT_OUTLAND);

for expId, zones in pairs(ZonesByExpansion) do
	for k, zoneId in ipairs(zones) do
		_V["WQT_ZONE_EXPANSIONS"][zoneId] = expId;
	end
end

_DeepWipeTable(ZonesByExpansion);

------------------------
-- SHARED
------------------------


_V["PATH_CUSTOM_ICONS"] = "Interface/Addons/WorldQuestTab/Images/CustomIcons";
_V["LIST_ANCHOR_TYPE"] = {["flight"] = 1, ["world"] = 2, ["full"] = 3, ["taxi"] = 4};
_V["CURRENT_EXPANSION"] = LE_EXPANSION_WAR_WITHIN;

_V["TOOLTIP_STYLES"] = { 
	["default"] = {},
	["callingAvailable"] = { ["hideObjectives"] = true; },
	["callingActive"] = { ["hideType"] = true; },
}

_V["COLOR_IDS"] = {
}

_V["WQT_COLOR_NONE"] =  CreateColor(0.45, 0.45, .45) ;
_V["WQT_COLOR_ARMOR"] =  CreateColor(0.85, 0.6, 1) ;
_V["WQT_COLOR_WEAPON"] =  CreateColor(1, 0.40, 1) ;
_V["WQT_COLOR_ARTIFACT"] = CreateColor(0, 0.75, 0);
_V["WQT_COLOR_CURRENCY"] = CreateColor(0.6, 0.4, 0.1) ;
_V["WQT_COLOR_GOLD"] = CreateColor(0.95, 0.8, 0) ;
_V["WQT_COLOR_HONOR"] = CreateColor(0.8, 0.26, 0);
_V["WQT_COLOR_ITEM"] = CreateColor(0.85, 0.85, 0.85) ;
_V["WQT_COLOR_MISSING"] = CreateColor(0.7, 0.1, 0.1);
_V["WQT_COLOR_RELIC"] = CreateColor(0.3, 0.7, 1);
_V["WQT_WHITE_FONT_COLOR"] = CreateColor(0.8, 0.8, 0.8);
_V["WQT_ORANGE_FONT_COLOR"] = CreateColor(1, 0.5, 0);
_V["WQT_GREEN_FONT_COLOR"] = CreateColor(0, 0.75, 0);
_V["WQT_BLUE_FONT_COLOR"] = CreateColor(0.2, 0.60, 1);
_V["WQT_PURPLE_FONT_COLOR"] = CreateColor(0.73, 0.33, 0.82);


_V["WQT_BOUNTYBOARD_OVERLAYID"] = 5;
_V["WQT_TYPE_BONUSOBJECTIVE"] = 99;
_V["WQT_LISTITTEM_HEIGHT"] = 32;

_V["DEBUG_OUTPUT_TYPE"] = {
	["invalid"] = 0
	,["setting"] = 1
	,["quest"] = 2
	,["worldQuest"] = 3
	,["addon"] = 4
}

_V["FILTER_TYPES"] = {
	["faction"] = 1
	,["type"] = 2
	,["reward"] = 3
}

_V["PIN_CENTER_TYPES"] =	{
	["blizzard"] = 1
	,["reward"] = 2
	,["faction"] = 3
}

_V["PIN_CENTER_LABELS"] ={
	[_V["PIN_CENTER_TYPES"].blizzard] = {["label"] = _L["BLIZZARD"], ["tooltip"] = _L["PIN_BLIZZARD_TT"]} 
	,[_V["PIN_CENTER_TYPES"].reward] = {["label"] = REWARD, ["tooltip"] = _L["PIN_REWARD_TT"]}
	,[_V["PIN_CENTER_TYPES"].faction] = {["label"] = FACTION, ["tooltip"] = _L["PIN_FACTION_TT"]}
}

_V["RING_TYPES"] = {
	["default"] = 1
	,["reward"] = 2
	,["time"] = 3
	,["rarity"] = 4
}

_V["RING_TYPES_LABELS"] ={
	[_V["RING_TYPES"].default] = {["label"] = _L["PIN_RING_DEFAULT"], ["tooltip"] = _L["PIN_RING_DEFAULT_TT"]} 
	,[_V["RING_TYPES"].reward] = {["label"] = _L["PIN_RING_COLOR"], ["tooltip"] = _L["PIN_RING_COLOR_TT"]}
	,[_V["RING_TYPES"].time] = {["label"] = _L["PIN_RING_TIME"], ["tooltip"] = _L["PIN_RIMG_TIME_TT"]}
	,[_V["RING_TYPES"].rarity] = {["label"] = RARITY, ["tooltip"] = _L["PIN_RING_QUALITY_TT"]}
}

_V["OPTIONAL_LABEL_TYPES"] = {
	["none"] = 1
	,["time"] = 2
	,["amount"] = 3
}

_V["OPTIONAL_LABEL_LABELS"] ={
	[_V["OPTIONAL_LABEL_TYPES"].none] = {["label"] = NONE, ["tooltip"] = _L["PIN_OPTIONAL_NONE_TT"]} 
	,[_V["OPTIONAL_LABEL_TYPES"].time] = {["label"] = _L["PIN_RING_TIME"], ["tooltip"] = _L["PIN_TIME_TT"]}
	,[_V["OPTIONAL_LABEL_TYPES"].amount] = {["label"] = _L["PIN_OPTIONAL_AMOUNT"], ["tooltip"] = _L["PIN_OPTIONAL_AMOUNT_TT"]}
}

_V["ENUM_PIN_CONTINENT"] = {
	["none"] = 1
	,["tracked"] = 2
	,["all"] = 3
}

_V["PIN_VISIBILITY_CONTINENT"] = {
	[_V["ENUM_PIN_CONTINENT"].none] = {["label"] = NONE, ["tooltip"] = _L["PIN_VISIBILITY_NONE_TT"]} 
	,[_V["ENUM_PIN_CONTINENT"].tracked] = {["label"] = _L["PIN_VISIBILITY_TRACKED"], ["tooltip"] = _L["PIN_VISIBILITY_TRACKED_TT"]} 
	,[_V["ENUM_PIN_CONTINENT"].all] = {["label"] = ALL, ["tooltip"] = _L["PIN_VISIBILITY_ALL_TT"]} 
}

_V["ENUM_PIN_ZONE"] = {
	["none"] = 1
	,["tracked"] = 2
	,["all"] = 3
}

_V["PIN_VISIBILITY_ZONE"] = {
	[_V["ENUM_PIN_ZONE"].none] = {["label"] = NONE, ["tooltip"] = _L["PIN_VISIBILITY_NONE_TT"]} 
	,[_V["ENUM_PIN_ZONE"].tracked] = {["label"] = _L["PIN_VISIBILITY_TRACKED"], ["tooltip"] = _L["PIN_VISIBILITY_TRACKED_TT"]} 
	,[_V["ENUM_PIN_ZONE"].all] = {["label"] = ALL, ["tooltip"] = _L["PIN_VISIBILITY_ALL_TT"]} 
}

_V["SETTING_TYPES"] = {
	["category"] = 1
	,["subTitle"] = 2
	,["checkBox"] = 3
	,["slider"] = 4
	,["dropDown"] = 5
	,["button"] = 6
}

local function MakeIndexArg1(list)
	for k, v in pairs(list) do
		v.arg1 = k;
	end
end

MakeIndexArg1(_V["PIN_CENTER_LABELS"]);
MakeIndexArg1(_V["RING_TYPES_LABELS"]);
MakeIndexArg1(_V["PIN_VISIBILITY_CONTINENT"]);
MakeIndexArg1(_V["PIN_VISIBILITY_ZONE"]);

-------------------------------
-- Settings List
-------------------------------
-- This list gets turned into a settings menu based on the data provided.
-- GENERAL
--   (either) template: A frame template which inherits the base mixin WQT_SettingsBaseMixin;
--   (or) frameName: The name of a specific frame using the mixin WQT_SettingsBaseMixin;
--   label (string): The text the label should have
--   tooltip (string): Text displayed in the tooltip
--   valueChangedFunc (function(value, ...)): what actions should be taken when the value is changed. Value is nil for buttons
--   isDisabled (boolean|function()): Boolean or function returning if the setting should be disabled
--   getValueFunc (function()): Function returning the current value of the setting
--   isNew (boolean): Mark the setting as new by adding an exclamantion mark to the label
-- SLIDER SPECIFIC
--   min (number): min value
--   max (number): max value
--   valueStep (number): step the slider makes when moved
-- COLOR SPECIFIC
--   defaultColor (Color): the default color for this setting
-- DROPDOWN SPECIFIC
--   options (table): a list for options in following format 
--			{[id1] = {["label"] = "Displayed label"
--			 		,["tooltip"] = "additional tooltip info (optional)"
--					,["arg1"] = required first return value
--					,["arg2"] = optional second return value in valueChangedFunc
--					}
--			 ,[id2] = ...}

_V["SETTING_CATEGORIES"] = {
	{["id"]="DEBUG", ["label"] = "Debug"}
	,{["id"]="PROFILES", ["label"] = _L["PROFILES"]}
	,{["id"]="GENERAL", ["label"] = GENERAL, ["expanded"] = true}
	,{["id"]="GENERAL_WAR_WITHIN", ["parentCategory"] = "GENERAL", ["label"] = EXPANSION_NAME10, ["expanded"] = false}
	,{["id"]="GENERAL_DRAGONFLIGHT", ["parentCategory"] = "GENERAL", ["label"] = EXPANSION_NAME9, ["expanded"] = false}
	,{["id"]="GENERAL_SHADOWLANDS", ["parentCategory"] = "GENERAL", ["label"] = EXPANSION_NAME8, ["expanded"] = false}
	,{["id"]="GENERAL_OLDCONTENT", ["parentCategory"] = "GENERAL", ["label"] = _L["PREVIOUS_EXPANSIONS"]}
	,{["id"]="QUESTLIST", ["label"] = _L["QUEST_LIST"]}
	,{["id"]="MAPPINS", ["label"] = _L["MAP_PINS"]}
	,{["id"]="MAPPINS_MINIICONS", ["parentCategory"] = "MAPPINS", ["label"] = _L["MINI_ICONS"], ["expanded"] = true}
	,{["id"]="COLORS", ["label"] = _L["CUSTOM_COLORS"]}
	,{["id"]="COLORS_TIME", ["parentCategory"] = "COLORS", ["label"] = _L["TIME_COLORS"], ["expanded"] = true}
	,{["id"]="COLORS_REWARD_RING", ["parentCategory"] = "COLORS", ["label"] = _L["REWARD_COLORS_RING"]}
	,{["id"]="COLORS_REWARD_AMOUNT", ["parentCategory"] = "COLORS", ["label"] = _L["REWARD_COLORS_AMOUNT"]}
	,{["id"]="WQTU", ["label"] = "Utilities"}
	,{["id"]="TOMTOM", ["label"] = "TomTom"}
}

local function UpdateColorID(id, r, g, b) 
	local color = WQT_Utils:UpdateColor(_V["COLOR_IDS"][id], r, g, b);
	if (color) then
		WQT.settings.colors[id] = color:GenerateHexColor();
		WQT_QuestScrollFrame:DisplayQuestList();
		WQT_WorldQuestFrame.pinDataProvider:RefreshAllData();
	end
end

local function GetColorByID(id)
	return WQT_Utils:GetColor(_V["COLOR_IDS"][id]);
end

_V["SETTING_LIST"] = {
	-- Time
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_TIME", ["label"] = _L["TIME_CRITICAL"], ["tooltip"] = _L["TIME_CRITICAL_TT"], ["defaultColor"] = RED_FONT_COLOR
			, ["valueChangedFunc"] = UpdateColorID, ["colorID"] = "timeCritical" ,["getValueFunc"] = GetColorByID
		},
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_TIME", ["label"] = _L["TIME_SHORT"], ["tooltip"] = _L["TIME_SHORT_TT"], ["defaultColor"] = _V["WQT_ORANGE_FONT_COLOR"]
			, ["valueChangedFunc"] = UpdateColorID, ["colorID"] = "timeShort",["getValueFunc"] = GetColorByID
		},
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_TIME", ["label"] = _L["TIME_MEDIUM"], ["tooltip"] = _L["TIME_MEDIUM_TT"], ["defaultColor"] = _V["WQT_GREEN_FONT_COLOR"]
			, ["valueChangedFunc"] = UpdateColorID, ["colorID"] = "timeMedium",["getValueFunc"] = GetColorByID
		},
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_TIME", ["label"] = _L["TIME_LONG"], ["tooltip"] = _L["TIME_LONG_TT"], ["defaultColor"] = _V["WQT_BLUE_FONT_COLOR"]
			, ["valueChangedFunc"] = UpdateColorID, ["colorID"] = "timeLong",["getValueFunc"] = GetColorByID
		},
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_TIME", ["label"] = _L["TIME_VERYLONG"], ["tooltip"] = _L["TIME_VERYLONG_TT"], ["defaultColor"] = _V["WQT_PURPLE_FONT_COLOR"]
			, ["valueChangedFunc"] = UpdateColorID, ["colorID"] = "timeVeryLong",["getValueFunc"] = GetColorByID
		},
	-- Rewards
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_RING", ["label"] = NONE, ["defaultColor"] = _V["WQT_COLOR_NONE"], 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardNone", ["getValueFunc"] = GetColorByID
		},
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_RING", ["label"] = WEAPON, ["defaultColor"] = _V["WQT_COLOR_WEAPON"], 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardWeapon", ["getValueFunc"] = GetColorByID
		},
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_RING", ["label"] = ARMOR, ["defaultColor"] = _V["WQT_COLOR_ARMOR"], 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardArmor", ["getValueFunc"] = GetColorByID
		},
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_RING", ["label"] = _L["REWARD_CONDUITS"], ["defaultColor"] = _V["WQT_COLOR_RELIC"], 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardConduit", ["getValueFunc"] = GetColorByID
		},
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_RING", ["label"] = RELICSLOT, ["defaultColor"] = _V["WQT_COLOR_RELIC"], 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardRelic", ["getValueFunc"] = GetColorByID
		},
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_RING", ["label"] = WORLD_QUEST_REWARD_FILTERS_ANIMA, ["defaultColor"] = _V["WQT_COLOR_ARTIFACT"], 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardAnima", ["getValueFunc"] = GetColorByID
		},
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_RING", ["label"] = ITEM_QUALITY6_DESC, ["defaultColor"] = _V["WQT_COLOR_ARTIFACT"], 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardArtifact", ["getValueFunc"] = GetColorByID
		},
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_RING", ["label"] = ITEMS, ["defaultColor"] = _V["WQT_COLOR_ITEM"], 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardItem", ["getValueFunc"] = GetColorByID
		},
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_RING", ["label"] = POWER_TYPE_EXPERIENCE, ["defaultColor"] = _V["WQT_COLOR_ITEM"], 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardXp", ["getValueFunc"] = GetColorByID
		},	
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_RING", ["label"] = WORLD_QUEST_REWARD_FILTERS_GOLD, ["defaultColor"] = _V["WQT_COLOR_GOLD"], 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardGold", ["getValueFunc"] = GetColorByID
		},
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_RING", ["label"] = CURRENCY, ["defaultColor"] = _V["WQT_COLOR_CURRENCY"], 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardCurrency", ["getValueFunc"] = GetColorByID
		},
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_RING", ["label"] = REPUTATION, ["defaultColor"] = _V["WQT_COLOR_CURRENCY"], 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardReputation", ["getValueFunc"] = GetColorByID
		},	
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_RING", ["label"] = HONOR, ["defaultColor"] = _V["WQT_COLOR_HONOR"], 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardHonor", ["getValueFunc"] = GetColorByID
		},
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_RING", ["label"] = ADDON_MISSING, ["defaultColor"] = _V["WQT_COLOR_MISSING"], 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardMissing", ["getValueFunc"] = GetColorByID
		},	
	-- Rewards
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_AMOUNT", ["label"] = WEAPON, ["defaultColor"] = _V["WQT_COLOR_WEAPON"], 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardTextWeapon", ["getValueFunc"] = GetColorByID
		},
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_AMOUNT", ["label"] = ARMOR, ["defaultColor"] = _V["WQT_COLOR_ARMOR"], 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardTextArmor", ["getValueFunc"] = GetColorByID
		},
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_AMOUNT", ["label"] = _L["REWARD_CONDUITS"], ["defaultColor"] = WHITE_FONT_COLOR, 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardTextConduit", ["getValueFunc"] = GetColorByID
		},
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_AMOUNT", ["label"] = RELICSLOT, ["defaultColor"] = WHITE_FONT_COLOR, 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardTextRelic", ["getValueFunc"] = GetColorByID
		},
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_AMOUNT", ["label"] = WORLD_QUEST_REWARD_FILTERS_ANIMA, ["defaultColor"] = GREEN_FONT_COLOR, 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardTextAnima", ["getValueFunc"] = GetColorByID
		},
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_AMOUNT", ["label"] = ITEM_QUALITY6_DESC, ["defaultColor"] = GREEN_FONT_COLOR, 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardTextArtifact", ["getValueFunc"] = GetColorByID
		},
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_AMOUNT", ["label"] = ITEMS, ["defaultColor"] = WHITE_FONT_COLOR, 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardTextItem", ["getValueFunc"] = GetColorByID
		},
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_AMOUNT", ["label"] = POWER_TYPE_EXPERIENCE, ["defaultColor"] = WHITE_FONT_COLOR, 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardTextXp", ["getValueFunc"] = GetColorByID
		},	
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_AMOUNT", ["label"] = WORLD_QUEST_REWARD_FILTERS_GOLD, ["defaultColor"] = WHITE_FONT_COLOR, 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardTextGold", ["getValueFunc"] = GetColorByID
		},
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_AMOUNT", ["label"] = CURRENCY, ["defaultColor"] = WHITE_FONT_COLOR, 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardTextCurrency", ["getValueFunc"] = GetColorByID
		},
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_AMOUNT", ["label"] = REPUTATION, ["defaultColor"] = WHITE_FONT_COLOR, 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardTextReputation", ["getValueFunc"] = GetColorByID
		},	
	{["template"] = "WQT_SettingColorTemplate", ["categoryID"] = "COLORS_REWARD_AMOUNT", ["label"] = HONOR, ["defaultColor"] = WHITE_FONT_COLOR, 
			["valueChangedFunc"] = UpdateColorID, ["colorID"] = "rewardTextHonor", ["getValueFunc"] = GetColorByID
		},
		
	{["template"] = "WQT_SettingProfileDropDownTemplate", ["categoryID"] = "PROFILES", ["label"] = _L["CURRENT_PROFILE"], ["tooltip"] = _L["CURRENT_PROFILE_TT"], ["options"] = function() return WQT_Profiles:GetProfiles() end
			, ["valueChangedFunc"] = function(arg1, arg2)
				if arg1 == WQT_Profiles:GetActiveProfileId() then
					-- Trying to load currently active profile
					return;
				end
				
				-- Load by index
				WQT_Profiles:LoadIndex(arg1);
				WQT_WorldQuestFrame:ApplyAllSettings();
			end
			,["getValueFunc"] = function() return WQT_Profiles:GetIndexById(WQT.db.char.activeProfile) end
			}
	,{["template"] = "WQT_SettingTextInputTemplate", ["categoryID"] = "PROFILES", ["label"] = _L["PROFILE_NAME"] , ["tooltip"] = _L["PROFILE_NAME_TT"] 
			, ["valueChangedFunc"] = function(value) 
				WQT_Profiles:ChangeActiveProfileName(value);
			end
			,["getValueFunc"] = function() 
				return WQT_Profiles:GetActiveProfileName(); 
			end
			,["isDisabled"] = function() return WQT_Profiles:DefaultIsActive() end
			}
	,{["template"] = "WQT_SettingButtonTemplate", ["categoryID"] = "PROFILES", ["label"] = _L["NEW_PROFILE"], ["tooltip"] = _L["NEW_PROFILE_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT_Profiles:CreateNew();
			end
			}
	,{["template"] = "WQT_SettingConfirmButtonTemplate", ["categoryID"] = "PROFILES", ["label"] =_L["RESET_PROFILE"], ["tooltip"] = _L["RESET_PROFILE_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT_Profiles:ResetActive();
				WQT_WorldQuestFrame:ApplyAllSettings();
			end
			}
	,{["template"] = "WQT_SettingConfirmButtonTemplate", ["categoryID"] = "PROFILES", ["label"] =_L["REMOVE_PROFILE"], ["tooltip"] = _L["REMOVE_PROFILE_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT_Profiles:Delete(WQT_Profiles:GetActiveProfileId());
				WQT_WorldQuestFrame:ApplyAllSettings();
			end
			,["isDisabled"] = function() return WQT_Profiles:DefaultIsActive()  end
			}
	-- General settings
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "GENERAL", ["label"] = _L["DEFAULT_TAB"], ["tooltip"] = _L["DEFAULT_TAB_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.general.defaultTab = value;
			end
			,["getValueFunc"] = function() return WQT.settings.general.defaultTab end
			}
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "GENERAL", ["label"] = _L["SAVE_SETTINGS"], ["tooltip"] = _L["SAVE_SETTINGS_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.general.saveFilters = value;
			end
			,["getValueFunc"] = function() return WQT.settings.general.saveFilters end
			}	
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "GENERAL", ["label"] = _L["PRECISE_FILTER"], ["tooltip"] = _L["PRECISE_FILTER_TT"]
			, ["valueChangedFunc"] = function(value) 
				for i=1, 3 do
					if (not WQT:IsUsingFilterNr(i)) then
						WQT:SetAllFilterTo(i, not value);
					end
				end
			
				WQT.settings.general.preciseFilters = value;
				WQT_QuestScrollFrame:DisplayQuestList();
			end
			,["getValueFunc"] = function() return WQT.settings.general.preciseFilters end
			}	
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "GENERAL", ["label"] = _L["LFG_BUTTONS"], ["tooltip"] = _L["LFG_BUTTONS_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.general.useLFGButtons = value;
			end
			,["getValueFunc"] = function() return WQT.settings.general.useLFGButtons end
			}	
		
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "GENERAL", ["label"] = _L["QUEST_COUNTER"], ["tooltip"] = _L["QUEST_COUNTER_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.general.questCounter = value;
				WQT_QuestLogFiller:UpdateVisibility();
			end
			,["getValueFunc"] = function() return WQT.settings.general.questCounter; end
			}
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "GENERAL", ["label"] = _L["ALWAYS_ALL"], ["tooltip"] = _L["ALWAYS_ALL_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.list.alwaysAllQuests = value;
				local mapAreaID = WorldMapFrame.mapID;
				WQT_WorldQuestFrame.dataProvider:LoadQuestsInZone(mapAreaID);
				WQT_QuestScrollFrame:UpdateQuestList();
			end
			,["getValueFunc"] = function() return WQT.settings.list.alwaysAllQuests end
			}	
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "GENERAL_SHADOWLANDS", ["label"] = _L["INCLUDE_DAILIES"], ["tooltip"] = _L["INCLUDE_DAILIES_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.list.includeDaily = value;
				local mapAreaID = WorldMapFrame.mapID;
				WQT_WorldQuestFrame.dataProvider:LoadQuestsInZone(mapAreaID);
				if (not value) then
					WQT_Utils:RefreshOfficialDataProviders();
				end
			end
			,["getValueFunc"] = function() return WQT.settings.list.includeDaily end
			}
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "GENERAL", ["label"] = _L["ALIGN_WORLDMAP_BUTTON"], ["tooltip"] = _L["ALIGN_WORLDMAP_BUTTON_TT"], ["isNew"] = true
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.general.alignWorldMapButton = value;
				WQT_WorldQuestFrame:UpdateWorldMapButton();
			end
			,["getValueFunc"] = function() return WQT.settings.general.alignWorldMapButton end
			}
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "GENERAL_DRAGONFLIGHT", ["label"] = _L["GOLD_PURSES"], ["tooltip"] = _L["GOLD_PURSES_TT"]
			, ["valueChangedFunc"] = function(value)
				WQT.settings.general.df_goldPurses = value;
				WQT_WorldQuestFrame.dataProvider:ReloadQuestRewards();
			end
			,["getValueFunc"] = function() return WQT.settings.general.df_goldPurses end
			}
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "GENERAL_SHADOWLANDS", ["label"] = _L["CALLINGS_BOARD"], ["tooltip"] = _L["CALLINGS_BOARD_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.general.sl_callingsBoard = value;
				WQT_CallingsBoard:UpdateVisibility();
			end
			,["getValueFunc"] = function() return WQT.settings.general.sl_callingsBoard end
			}
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "GENERAL_SHADOWLANDS", ["label"] = _L["GENERIC_ANIMA"], ["tooltip"] = _L["GENERIC_ANIMA_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.general.sl_genericAnimaIcons = value;
				WQT_WorldQuestFrame.dataProvider:ReloadQuestRewards();
			end
			,["getValueFunc"] = function() return WQT.settings.general.sl_genericAnimaIcons end
			}
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "GENERAL_OLDCONTENT", ["label"] = _L["AUTO_EMISARRY"], ["tooltip"] = _L["AUTO_EMISARRY_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.general.autoEmissary = value;
			end
			,["getValueFunc"] = function() return WQT.settings.general.autoEmissary end
			}	
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "GENERAL_OLDCONTENT", ["label"] = _L["EMISSARY_COUNTER"], ["tooltip"] = _L["EMISSARY_COUNTER_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.general.bountyCounter = value;
				WQT_WorldQuestFrame:UpdateBountyCounters();
				WQT_WorldQuestFrame:RepositionBountyTabs();
			end
			,["getValueFunc"] = function() return WQT.settings.general.bountyCounter end
			}	
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "GENERAL_OLDCONTENT", ["label"] = _L["EMISSARY_REWARD"], ["tooltip"] = _L["EMISSARY_REWARD_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.general.bountyReward = value;
				WQT_WorldQuestFrame:UpdateBountyCounters();
			end
			,["getValueFunc"] = function() return WQT.settings.general.bountyReward end
			}
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "GENERAL_OLDCONTENT", ["label"] = _L["EMISSARY_SELECTED_ONLY"], ["tooltip"] = _L["EMISSARY_SELECTED_ONLY_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.general.bountySelectedOnly = value;
				WQT_QuestScrollFrame:UpdateQuestList();
			end
			,["getValueFunc"] = function() return WQT.settings.general.bountySelectedOnly end
			}
	-- Quest List
	,{["frameName"] = "WQT_SettingsQuestListPreview", ["categoryID"] = "QUESTLIST"}	
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "QUESTLIST", ["label"] = _L["SHOW_TYPE"], ["tooltip"] = _L["SHOW_TYPE_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.list.typeIcon = value;
				WQT_QuestScrollFrame:DisplayQuestList();
			end
			,["getValueFunc"] = function() return WQT.settings.list.typeIcon end
			}	
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "QUESTLIST", ["label"] = _L["SHOW_FACTION"], ["tooltip"] = _L["SHOW_FACTION_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.list.factionIcon = value;
				WQT_QuestScrollFrame:DisplayQuestList();
			end
			,["getValueFunc"] = function() return WQT.settings.list.factionIcon end
			}	
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "QUESTLIST", ["label"] = _L["SHOW_ZONE"], ["tooltip"] = _L["SHOW_ZONE_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.list.showZone = value;
				WQT_QuestScrollFrame:DisplayQuestList();
			end
			,["getValueFunc"] = function() return WQT.settings.list.showZone end
			}
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "QUESTLIST", ["label"] = _L["SHOW_WARBAND_BONUS"], ["tooltip"] = _L["SHOW_WARBAND_BONUS_TT"], ["isNew"] = true
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.list.showWarbandBonus = value;
				WQT_QuestScrollFrame:DisplayQuestList();
			end
			,["getValueFunc"] = function() return WQT.settings.list.showWarbandBonus end
			}
	,{["template"] = "WQT_SettingSliderTemplate", ["categoryID"] = "QUESTLIST", ["label"] = _L["REWARD_NUM_DISPLAY"], ["tooltip"] = _L["REWARD_NUM_DISPLAY_TT"], ["min"] = 0, ["max"] = 3, ["valueStep"] = 1
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.list.rewardNumDisplay = value;
				WQT_QuestScrollFrame:DisplayQuestList();
			end
			,["getValueFunc"] = function() return WQT.settings.list.rewardNumDisplay end
			}
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "QUESTLIST", ["label"] = _L["AMOUNT_COLORS"], ["tooltip"] = _L["AMOUNT_COLORS_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.list.amountColors = value;
				WQT_QuestScrollFrame:DisplayQuestList();
			end
			,["getValueFunc"] = function() return WQT.settings.list.amountColors end
			}
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "QUESTLIST", ["label"] = _L["LIST_COLOR_TIME"], ["tooltip"] = _L["LIST_COLOR_TIME_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.list.colorTime = value;
				WQT_QuestScrollFrame:DisplayQuestList();
			end
			,["getValueFunc"] = function() return WQT.settings.list.colorTime end
			}
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "QUESTLIST", ["label"] = _L["LIST_FULL_TIME"], ["tooltip"] = _L["LIST_FULL_TIME_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.list.fullTime = value;
				WQT_QuestScrollFrame:DisplayQuestList();
			end
			,["getValueFunc"] = function() return WQT.settings.list.fullTime end
			}	
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "QUESTLIST", ["label"] = _L["PIN_FADE_ON_PING"], ["tooltip"] = _L["PIN_FADE_ON_PING_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.pin.fadeOnPing = value;
			end
			,["getValueFunc"] = function() return WQT.settings.pin.fadeOnPing end
			,["isDisabled"] = function() return WQT.settings.pin.disablePoI end
			}
	-- Map Pin
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "MAPPINS", ["label"] = _L["PIN_DISABLE"], ["tooltip"] = _L["PIN_DISABLE_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.pin.disablePoI = value;
				WQT_WorldQuestFrame.pinDataProvider:RefreshAllData()
				if (value) then
					WQT_Utils:RefreshOfficialDataProviders();
				end
			end
			,["getValueFunc"] = function() return WQT.settings.pin.disablePoI end
			}
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "MAPPINS", ["label"] = _L["FILTER_PINS"], ["tooltip"] = _L["FILTER_PINS_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.pin.filterPoI = value;
				WQT_WorldQuestFrame.pinDataProvider:RefreshAllData();
			end
			,["getValueFunc"] = function() return WQT.settings.pin.filterPoI end
			,["isDisabled"] = function() return WQT.settings.pin.disablePoI end
			}		
	--[[,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "MAPPINS", ["label"] = _L["PIN_SHOW_CONTINENT"], ["tooltip"] = _L["PIN_SHOW_CONTINENT_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.pin.continentPins = value;
				WQT_WorldQuestFrame.pinDataProvider:RefreshAllData();
			end
			,["getValueFunc"] = function() return WQT.settings.pin.continentPins end
			,["isDisabled"] = function() return WQT.settings.pin.disablePoI end
			}
			]]--
	-- Pin appearance
	,{["template"] =" WQT_SettingSubTitleTemplate", ["categoryID"] = "MAPPINS", ["label"] = APPEARANCE_LABEL}
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "MAPPINS", ["label"] =  _L["PIN_WARBAND_BONUS"], ["tooltip"] = _L["PIN_WARBAND_BONUS_TT"], ["isNew"] = true
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.pin.showWarbandBonus  = value;
				WQT_WorldQuestFrame.pinDataProvider:RefreshAllData();
			end
			,["getValueFunc"] = function() return WQT.settings.pin.showWarbandBonus end
			,["isDisabled"] = function() return WQT.settings.pin.disablePoI end
			}		
	
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "MAPPINS", ["label"] = _L["PIN_ELITE_RING"], ["tooltip"] = _L["PIN_ELITE_RING_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.pin.eliteRing  = value;
				WQT_WorldQuestFrame.pinDataProvider:RefreshAllData();
			end
			,["getValueFunc"] = function() return WQT.settings.pin.eliteRing end
			,["isDisabled"] = function() return WQT.settings.pin.disablePoI end
			}
	,{["template"] = "WQT_SettingSliderTemplate", ["categoryID"] = "MAPPINS", ["label"] = _L["PIN_SCALE"], ["tooltip"] = _L["PIN_SCALE_TT"], ["min"] = 0.8, ["max"] = 1.5, ["valueStep"] = 0.01
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.pin.scale = value;
				WQT_WorldQuestFrame.pinDataProvider:RefreshAllData();
			end
			,["getValueFunc"] = function() return WQT.settings.pin.scale end
			,["isDisabled"] = function() return WQT.settings.pin.disablePoI end
			}
	,{["template"] = "WQT_SettingDropDownTemplate", ["categoryID"] = "MAPPINS", ["label"] = _L["PIN_CENTER"], ["tooltip"] = _L["PIN_CENTER_TT"], ["isNew"] = true, ["options"] = _V["PIN_CENTER_LABELS"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.pin.centerType = value;
				WQT_WorldQuestFrame.pinDataProvider:RefreshAllData();
			end
			,["getValueFunc"] = function() return WQT.settings.pin.centerType end
			,["isDisabled"] = function() return WQT.settings.pin.disablePoI end
			}
	,{["template"] = "WQT_SettingDropDownTemplate", ["categoryID"] = "MAPPINS", ["label"] = _L["PIN_RING_TITLE"], ["tooltip"] = _L["PIN_RING_TT"], ["options"] = _V["RING_TYPES_LABELS"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.pin.ringType = value;
				WQT_WorldQuestFrame.pinDataProvider:RefreshAllData();
			end
			,["getValueFunc"] = function() return WQT.settings.pin.ringType end
			,["isDisabled"] = function() return WQT.settings.pin.disablePoI end
			}	
	,{["template"] = "WQT_SettingDropDownTemplate", ["categoryID"] = "MAPPINS", ["label"] = _L["PIN_OPTIONAL_LABEL"], ["tooltip"] = _L["PIN_OPTIONAL_LABEL_TT"], ["options"] = _V["OPTIONAL_LABEL_LABELS"], ["isNew"] = true
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.pin.optionalLabel = value;
				WQT_WorldQuestFrame.pinDataProvider:RefreshAllData();
			end
			,["getValueFunc"] = function() return WQT.settings.pin.optionalLabel end
			,["isDisabled"] = function() return WQT.settings.pin.disablePoI end
			}	
	,{["template"] = "WQT_SettingDropDownTemplate", ["categoryID"] = "MAPPINS", ["label"] = _L["PIN_VISIBILITY_ZONE"], ["tooltip"] = _L["PIN_VISIBILITY_ZONE_TT"], ["options"] = _V["PIN_VISIBILITY_ZONE"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.pin.zoneVisible = value;
				WQT_WorldQuestFrame.pinDataProvider:RefreshAllData();
			end
			,["getValueFunc"] = function() return WQT.settings.pin.zoneVisible end
			,["isDisabled"] = function() return WQT.settings.pin.disablePoI end
			}
	,{["template"] = "WQT_SettingDropDownTemplate", ["categoryID"] = "MAPPINS", ["label"] = _L["PIN_VISIBILITY_CONTINENT"], ["tooltip"] = _L["PIN_VISIBILITY_CONTINENT_TT"], ["options"] = _V["PIN_VISIBILITY_CONTINENT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.pin.continentVisible = value;
				WQT_WorldQuestFrame.pinDataProvider:RefreshAllData();
			end
			,["getValueFunc"] = function() return WQT.settings.pin.continentVisible end
			,["isDisabled"] = function() return WQT.settings.pin.disablePoI end
			}
	-- Pin icons
	--,{["template"] = "WQT_SettingSubTitleTemplate", ["categoryID"] = "MAPPINS", ["label"] = _L["MINI_ICONS"]}
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "MAPPINS_MINIICONS", ["label"] = _L["PIN_TYPE"], ["tooltip"] = _L["PIN_TYPE_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.pin.typeIcon = value;
				WQT_WorldQuestFrame.pinDataProvider:RefreshAllData()
			end
			,["getValueFunc"] = function()  return WQT.settings.pin.typeIcon; end
			,["isDisabled"] = function() return WQT.settings.pin.disablePoI; end
			}
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "MAPPINS_MINIICONS", ["label"] = _L["PIN_RARITY_ICON"], ["tooltip"] = _L["PIN_RARITY_ICON_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.pin.rarityIcon = value;
				WQT_WorldQuestFrame.pinDataProvider:RefreshAllData()
			end
			,["getValueFunc"] = function() return WQT.settings.pin.rarityIcon; end
			,["isDisabled"] = function() return WQT.settings.pin.disablePoI;  end
			}		
	,{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "MAPPINS_MINIICONS", ["label"] = _L["PIN_TIME_ICON"], ["tooltip"] = _L["PIN_TIME_ICON_TT"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.pin.timeIcon = value;
				WQT_WorldQuestFrame.pinDataProvider:RefreshAllData()
			end
			,["getValueFunc"] = function() return WQT.settings.pin.timeIcon; end
			,["isDisabled"] = function() return WQT.settings.pin.disablePoI;  end
			}	
	,{["template"] = "WQT_SettingSliderTemplate", ["categoryID"] = "MAPPINS_MINIICONS", ["label"] = _L["REWARD_NUM_DISPLAY_PIN"], ["tooltip"] = _L["REWARD_NUM_DISPLAY_PIN_TT"], ["min"] = 0, ["max"] = 3, ["valueStep"] = 1
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.pin.numRewardIcons = value;
				WQT_WorldQuestFrame.pinDataProvider:RefreshAllData();
			end
			,["getValueFunc"] = function() return WQT.settings.pin.numRewardIcons end
			,["isDisabled"] = function() return WQT.settings.pin.disablePoI; end
			}
}

--[[_V["SETTING_UTILITIES_LIST"] = {
	{["template"] = "WQT_SettingCheckboxTemplate", ["categoryID"] = "WQTU", ["label"] = _L["LOAD_UTILITIES"], ["tooltip"] = _L["LOAD_UTILITIES_TT"], ["disabledTooltip"] = _L["LOAD_UTILITIES_TT_DISABLED"]
			, ["valueChangedFunc"] = function(value) 
				WQT.settings.general.loadUtilities = value;
				if (value and not IsAddOnLoaded("WorldQuestTabUtilities")) then
					LoadAddOn("WorldQuestTabUtilities");
					WQT_QuestScrollFrame:UpdateQuestList();
				end
			end
			,["getValueFunc"] = function() return WQT.settings.general.loadUtilities end
			,["isDisabled"] = function() return GetAddOnEnableState(nil, "WorldQuestTabUtilities") == 0 end
			}	
}]]

_V["TIME_REMAINING_CATEGORY"] = {
	["none"] = 0
	,["expired"] = 1
	,["critical"] = 2 -- <15m
	,["short"] = 3 -- 1h
	,["medium"] = 4 -- 24h
	,["long"] = 5 -- 3d
	,["veryLong"] = 6 -- >3d
}

_V["QUESTS_NOT_COUNTING"] = {
		[261] = true -- Account Wide
		,[256] = true -- PvP Conquest
		,[102] = true -- Island Weekly Quest
		,[270] = true -- Threat Emissary
	}

_V["NUMBER_ABBREVIATIONS_ASIAN"] = {
		{["value"] = 10000000000000, ["format"] = _L["NUMBERS_THIRD"]}
		,{["value"] = 1000000000000, ["format"] = _L["NUMBERS_THIRD"], ["decimal"] = true}
		,{["value"] = 1000000000, ["format"] = _L["NUMBERS_SECOND"]}
		,{["value"] = 100000000, ["format"] = _L["NUMBERS_SECOND"], ["decimal"] = true}
		,{["value"] = 100000, ["format"] = _L["NUMBERS_FIRST"]}
		,{["value"] = 10000, ["format"] = _L["NUMBERS_FIRST"], ["decimal"] = true}
	}

_V["NUMBER_ABBREVIATIONS"] = {
		{["value"] = 10000000000, ["format"] = _L["NUMBERS_THIRD"]}
		,{["value"] = 1000000000, ["format"] = _L["NUMBERS_THIRD"], ["decimal"] = true}
		,{["value"] = 10000000, ["format"] = _L["NUMBERS_SECOND"]}
		,{["value"] = 1000000, ["format"] = _L["NUMBERS_SECOND"], ["decimal"] = true}
		,{["value"] = 10000, ["format"] = _L["NUMBERS_FIRST"]}
		,{["value"] = 1000, ["format"] = _L["NUMBERS_FIRST"], ["decimal"] = true}
	}

_V["WARMODE_BONUS_REWARD_TYPES"] = {
		[WQT_REWARDTYPE.artifact] = true;
		[WQT_REWARDTYPE.gold] = true;
		[WQT_REWARDTYPE.currency] = true;
	}

_V["WQT_CVAR_LIST"] = {
		["Petbattle"] = "showTamersWQ"
		,["Anima"] = "worldQuestFilterAnima"
		,["Artifact"] = "worldQuestFilterArtifactPower"
		,["Armor"] = "worldQuestFilterEquipment"
		,["Gold"] = "worldQuestFilterGold"
		,["Currency"] = "worldQuestFilterResources"
		,["Profession"] = "worldQuestFilterProfessionMaterials"
		,["Reputation"] = "worldQuestFilterReputation"
		,["Skyriding"] = "dragonRidingRacesFilterWQ"
	}
	
_V["WQT_TYPEFLAG_LABELS"] = {
		[2] = {["Default"] = DEFAULT, ["Elite"] = ELITE, ["PvP"] = PVP, ["Petbattle"] = PET_BATTLE_PVP_QUEUE, ["Dungeon"] = TRACKER_HEADER_DUNGEON, ["Raid"] = RAID, ["Profession"] = BATTLE_PET_SOURCE_4, ["Invasion"] = _L["TYPE_INVASION"], ["Assault"] = SPLASH_BATTLEFORAZEROTH_8_1_FEATURE2_TITLE
			, ["Daily"] = DAILY, ["Threat"] = REPORT_THREAT, ["Bonus"] = SCENARIO_BONUS_LABEL, ["Skyriding"] = DRAGONRIDING_RACES_MAP_TOGGLE}
		,[3] = {["Item"] = ITEMS, ["Armor"] = WORLD_QUEST_REWARD_FILTERS_EQUIPMENT, ["Gold"] = WORLD_QUEST_REWARD_FILTERS_GOLD, ["Currency"] = CURRENCY, ["Artifact"] = ITEM_QUALITY6_DESC, ["Anima"] = WORLD_QUEST_REWARD_FILTERS_ANIMA, ["Conduits"] = _L["REWARD_CONDUITS"]
			, ["Relic"] = RELICSLOT, ["None"] = NONE, ["Experience"] = POWER_TYPE_EXPERIENCE, ["Honor"] = HONOR, ["Reputation"] = REPUTATION}
	};
	
_V["FILTER_TYPE_OLD_CONTENT"] = {
	[2] = {["Invasion"] = true, ["Assault"] = true, ["Threat"] = true}
	,[3] = {["Anima"] = true, ["Conduits"] = true, ["Artifact"] = true, ["Relic"] = true}
}

_V["WQT_SORT_OPTIONS"] = {[1] = _L["TIME"], [2] = FACTION, [3] = TYPE, [4] = ZONE, [5] = NAME, [6] = REWARD, [7] = QUALITY}
_V["SORT_OPTION_ORDER"] = {
	[1] = {"seconds", "rewardType", "rewardQuality", "rewardAmount", "canUpgrade", "rewardId", "title"},
	[2] = {"faction", "rewardType", "rewardQuality", "rewardAmount", "canUpgrade", "rewardId", "seconds", "title"},
	[3] = {"criteria", "questType", "questRarity", "elite", "rewardType", "rewardQuality", "rewardAmount", "canUpgrade", "rewardId", "seconds", "title"},
	[4] = {"zone", "rewardType", "rewardQuality", "rewardAmount", "canUpgrade", "rewardId", "seconds", "title"},
	[5] = {"title", "rewardType", "rewardQuality", "rewardAmount", "canUpgrade", "rewardId", "seconds"},
	[6] = {"rewardType", "rewardQuality", "rewardAmount", "canUpgrade", "rewardId", "seconds", "title"},
	[7] = {"rewardQuality", "rewardType", "rewardAmount", "canUpgrade", "rewardId", "seconds", "title"},
}
_V["SORT_FUNCTIONS"] = {
	["rewardType"] = function(a, b) 
			local aType, aSubType = a:GetRewardType();
			local bType, bSubType = b:GetRewardType();
			if (aType and bType and aType ~= bType) then 
				if (aType == WQT_REWARDTYPE.none or bType == WQT_REWARDTYPE.none) then
					return aType > bType; 
				end
				return aType < bType;
			elseif (aType == bType and aSubType and bSubType) then
				return aSubType < bSubType;
			end 
		end
	,["rewardQuality"] = function(a, b) 
			local aQuality = a:GetRewardQuality();
			local bQuality = b:GetRewardQuality();
			if (aQuality and bQuality and aQuality ~= bQuality) then 
				return aQuality > bQuality; 
			end 
		end
	,["canUpgrade"] = function(a, b) 
			local aCanUpgrade = a:GetRewardCanUpgrade();
			local bCanUpgrade = b:GetRewardCanUpgrade();
			if (aCanUpgrade and bCanUpgrade and aCanUpgrade ~= bCanUpgrade) then
				return aCanUpgrade and not bCanUpgrade; 
			end
		end
	,["seconds"] = function(a, b) if (a.time.seconds ~= b.time.seconds) then return a.time.seconds < b.time.seconds; end end
	,["rewardAmount"] = function(a, b) 
			local amountA = a:GetRewardAmount();
			local amountB = b:GetRewardAmount();
			if (C_PvP.IsWarModeDesired()) then
				local aType = a:GetRewardType();
				local bType = b:GetRewardType();
				local bonus = C_PvP.GetWarModeRewardBonus() / 100;
				if (_V["WARMODE_BONUS_REWARD_TYPES"][aType] and C_QuestLog.QuestHasWarModeBonus(a.questID)) then
					amountA = amountA + floor(amountA * bonus);
				end
				if (_V["WARMODE_BONUS_REWARD_TYPES"][bType] and C_QuestLog.QuestHasWarModeBonus(b.questID)) then
					amountB = amountB + floor(amountB * bonus);
				end
			end

			if (amountA ~= amountB) then 
				return amountA > amountB;
			end 
		end
	,["rewardId"] = function(a, b)
			local aId = a:GetRewardId();
			local bId = b:GetRewardId();
			if (aId and bId and aId ~= bId) then 
				return aId < bId; 
			end 
		end
	,["faction"] = function(a, b) 
			local _, factionIdA = C_TaskQuest.GetQuestInfoByQuestID(a.questID);
			local _, factionIdB = C_TaskQuest.GetQuestInfoByQuestID(b.questID);
			if (factionIdA ~= factionIdB) then 
				local factionA = WQT_Utils:GetFactionDataInternal(factionIdA);
				local factionB = WQT_Utils:GetFactionDataInternal(factionIdB);
				return factionA.name < factionB.name; 
			end 
		end
	,["questType"] = function(a, b) 
			if (a.isQuestStart ~= b.isQuestStart) then
				return a.isQuestStart and not b.isQuestStart;
			end		
			if (a.isDaily ~= b.isDaily) then
				return a.isDaily and not b.isDaily;
			end			
			
			local tagInfoA = a:GetTagInfo();
			local tagInfoB = b:GetTagInfo();
			if (tagInfoA and tagInfoB and tagInfoA.worldQuestType and tagInfoB.worldQuestType and tagInfoA.worldQuestType ~= tagInfoB.worldQuestType) then 
				return tagInfoA.worldQuestType > tagInfoB.worldQuestType; 
			end 
		end
	,["questRarity"] = function(a, b)
			local tagInfoA = a:GetTagInfo();
			local tagInfoB = b:GetTagInfo();
			if (tagInfoA and tagInfoB and tagInfoA.quality and tagInfoB.quality and tagInfoA.quality ~= tagInfoB.quality) then 
				return tagInfoA.quality > tagInfoB.quality; 
			end 
		end
	,["title"] = function(a, b)
			local titleA = C_TaskQuest.GetQuestInfoByQuestID(a.questID);
			local titleB = C_TaskQuest.GetQuestInfoByQuestID(b.questID);
			if (titleA ~= titleB) then 
				return titleA < titleB;
			end 
		end
	,["elite"] = function(a, b) 
			local tagInfoA = a:GetTagInfo();
			local tagInfoB = b:GetTagInfo();
			local aIsElite = tagInfoA and tagInfoA.isElite;
			local bIsElite = tagInfoB and tagInfoB.isElite;
			if (aIsElite ~= bIsElite) then 
				return aIsElite and not bIsElite; 
			end 
		end
	,["criteria"] = function(a, b) 
			local aIsCriteria = a:IsCriteria(WQT.settings.general.bountySelectedOnly);
			local bIsCriteria = b:IsCriteria(WQT.settings.general.bountySelectedOnly);
			if (aIsCriteria ~= bIsCriteria) then return aIsCriteria and not bIsCriteria; end 
		end
	,["zone"] = function(a, b) 
			local mapInfoA = WQT_Utils:GetMapInfoForQuest(a.questID);
			local mapInfoB = WQT_Utils:GetMapInfoForQuest(b.questID);
			if (mapInfoA and mapInfoA.name and mapInfoB and mapInfoB.name and mapInfoA.mapID ~= mapInfoB.mapID) then 
				if (WQT.settings.list.alwaysAllQuests and (mapInfoA.mapID == WorldMapFrame.mapID or mapInfoB.mapID == WorldMapFrame.mapID)) then 
					return mapInfoA.mapID == WorldMapFrame.mapID and mapInfoB.mapID ~= WorldMapFrame.mapID;
				end
				return mapInfoA.name < mapInfoB.name;
			end
		end
}
	
_V["REWARD_TYPE_ATLAS"] = {
		[WQT_REWARDTYPE.weapon] = {["texture"] =  "Interface/MINIMAP/POIIcons", ["scale"] = 1, ["l"] = 0.211, ["r"] = 0.277, ["t"] = 0.246, ["b"] = 0.277} -- Weapon
		,[WQT_REWARDTYPE.equipment] = {["texture"] =  "Interface/MINIMAP/POIIcons", ["scale"] = 1, ["l"] = 0.847, ["r"] = 0.91, ["t"] = 0.459, ["b"] = 0.49} -- Armor
		,[WQT_REWARDTYPE.relic] = {["texture"] = "poi-scrapper", ["scale"] = 1} -- Relic
		,[WQT_REWARDTYPE.artifact] = {["texture"] = "AzeriteReady", ["scale"] = 1.3} -- Azerite
		,[WQT_REWARDTYPE.item] = {["texture"] = "Banker", ["scale"] = 1.1} -- Item
		,[WQT_REWARDTYPE.gold] = {["texture"] = "Auctioneer", ["scale"] = 1} -- Gold
		,[WQT_REWARDTYPE.currency] = {["texture"] =  "Interface/MINIMAP/POIIcons", ["scale"] = 1, ["l"] = 0.4921875, ["r"] = 0.55859375, ["t"] = 0.0390625, ["b"] = 0.068359375, ["color"] = CreateColor(0.7, 0.52, 0.43)} -- Resources
		,[WQT_REWARDTYPE.honor] = {["texture"] = _playerFaction == "Alliance" and "poi-alliance" or "poi-horde", ["scale"] = 1} -- Honor
		,[WQT_REWARDTYPE.reputation] = {["texture"] = "QuestRepeatableTurnin", ["scale"] = 1.2} -- Rep
		,[WQT_REWARDTYPE.xp] = {["texture"] = "poi-door-arrow-up", ["scale"] = .9} -- xp
		,[WQT_REWARDTYPE.spell] = {["texture"] = "Banker", ["scale"] = 1.1}  -- spell acts like item
		,[WQT_REWARDTYPE.anima] = {["texture"] =  "Interface/Addons/WorldQuestTab/Images/AnimaIcon", ["scale"] = 1.15, ["l"] = 0, ["r"] = 1, ["t"] = 0, ["b"] = 1, ["color"] = CreateColor(0.8, 0.8, 0.9)} -- Anima
		,[WQT_REWARDTYPE.conduit] = {
			[_V["CONDUIT_SUBTYPE"].potency] = {["texture"] =  "soulbinds_tree_conduit_icon_attack", ["scale"] = 1.15};
			[_V["CONDUIT_SUBTYPE"].endurance] = {["texture"] =  "soulbinds_tree_conduit_icon_protect", ["scale"] = 1.15};
			[_V["CONDUIT_SUBTYPE"].finesse] = {["texture"] =  "soulbinds_tree_conduit_icon_utility", ["scale"] = 1.15};
		}-- Conduits
	}	

_V["FILTER_FUNCTIONS"] = {
		[2] = { -- Types
			["PvP"]			= function(questInfo, tagInfo) return tagInfo and (tagInfo.worldQuestType == Enum.QuestTagType.PvP or tagInfo.worldQuestType == Enum.QuestTagType.Bounty); end 
			,["Petbattle"]	= function(questInfo, tagInfo) return tagInfo and tagInfo.worldQuestType == Enum.QuestTagType.PetBattle; end 
			,["Dungeon"]	= function(questInfo, tagInfo) return tagInfo and tagInfo.worldQuestType == Enum.QuestTagType.Dungeon; end 
			,["Raid"]		= function(questInfo, tagInfo) return tagInfo and tagInfo.worldQuestType == Enum.QuestTagType.Raid; end 
			,["Profession"]	= function(questInfo, tagInfo) return tagInfo and tagInfo.worldQuestType == Enum.QuestTagType.Profession; end 
			,["Invasion"]	= function(questInfo, tagInfo) return tagInfo and (tagInfo.worldQuestType == Enum.QuestTagType.Invasion or tagInfo.worldQuestType == Enum.QuestTagType.InvasionWrapper); end 
			,["Assault"]	= function(questInfo, tagInfo) return tagInfo and tagInfo.worldQuestType == Enum.QuestTagType.FactionAssault; end 
			,["Elite"]		= function(questInfo, tagInfo) return tagInfo and tagInfo.isElite and tagInfo.worldQuestType ~= Enum.QuestTagType.Dungeon; end
			,["Default"]	= function(questInfo, tagInfo) return tagInfo and ((not tagInfo.isElite and tagInfo.worldQuestType == Enum.QuestTagType.Normal) or tagInfo.worldQuestType == Enum.QuestTagType.CovenantCalling); end 
			,["Daily"]		= function(questInfo, tagInfo) return questInfo.isDaily; end 
			,["Threat"]		= function(questInfo, tagInfo) return C_QuestLog.IsThreatQuest(questInfo.questID); end 
			,["Bonus"]		= function(questInfo, tagInfo) return not tagInfo; end
			,["Skyriding"]	= function(questInfo, tagInfo) return tagInfo and tagInfo.worldQuestType == Enum.QuestTagType.DragonRiderRacing; end
			}
		,[3] = { -- Reward filters
			["Armor"]		= function(questInfo, tagInfo) return bit.band(questInfo.reward.typeBits, WQT_REWARDTYPE.equipment + WQT_REWARDTYPE.weapon) > 0; end
			,["Relic"]		= function(questInfo, tagInfo) return bit.band(questInfo.reward.typeBits, WQT_REWARDTYPE.relic) > 0; end
			,["Item"]		= function(questInfo, tagInfo) return bit.band(questInfo.reward.typeBits, WQT_REWARDTYPE.spell + WQT_REWARDTYPE.item) > 0; end
			,["Anima"]		= function(questInfo, tagInfo) return bit.band(questInfo.reward.typeBits, WQT_REWARDTYPE.anima) > 0; end
			,["Conduits"]	= function(questInfo, tagInfo) return bit.band(questInfo.reward.typeBits, WQT_REWARDTYPE.conduit) > 0; end
			,["Artifact"]	= function(questInfo, tagInfo) return bit.band(questInfo.reward.typeBits, WQT_REWARDTYPE.artifact) > 0; end
			,["Honor"]		= function(questInfo, tagInfo) return bit.band(questInfo.reward.typeBits, WQT_REWARDTYPE.honor) > 0; end
			,["Gold"]		= function(questInfo, tagInfo) return bit.band(questInfo.reward.typeBits, WQT_REWARDTYPE.gold) > 0; end
			,["Currency"]	= function(questInfo, tagInfo) return bit.band(questInfo.reward.typeBits, WQT_REWARDTYPE.currency) > 0; end
			,["Experience"]	= function(questInfo, tagInfo) return bit.band(questInfo.reward.typeBits, WQT_REWARDTYPE.xp) > 0; end
			,["Reputation"]	= function(questInfo, tagInfo) return bit.band(questInfo.reward.typeBits, WQT_REWARDTYPE.reputation) > 0; end
			,["None"]		= function(questInfo, tagInfo) return questInfo.reward.typeBits == WQT_REWARDTYPE.none; end
			}
	};
-- /dump WorldMapFrame:GetMapID()
-- /dump FlightMapFrame:GetMapID()
_V["WQT_CONTINENT_GROUPS"] = {
		[2200] = {1978,2133} -- Emerald Dream 
		,[2241] = {1978,2133} -- Emerald Dream flightmap
		,[2133] = {1978,2200} -- Zaralek Cavern 
		,[2175] = {1978,2200} -- Zaralek Cavern flightmap
		,[1978] = {2133,2200} -- Dragonflight
		,[2057] = {2133,2200} -- Dragonflight flightmap
		,[875]	= {876, 1355} -- Zandalar
		,[1011]	= {876, 1355} -- Zandalar flightmap
		,[876]	= {875, 1355} -- Kul Tiras
		,[1014]	= {875, 1355} -- Kul Tiras flightmap
		,[1355]	= {875, 876} -- Nazjatar
		,[1504]	= {875, 876} -- Nazjatar flightmap
		,[619]	= {905} -- Legion
		,[905]	= {619} -- Argus
		
	}

_V["ZONE_SUBZONES"] = {
	[2255] = {2256, 2213, 2216}; -- Azj-Kahet, Azj-Kahet - Lower, City of Threads, City of Threads - Lower
	[2256] = {2255, 2213, 2216}; -- Azj-Kahet - Lower, Azj-Kahet, City of Threads, City of Threads - Lower
	[2025] = {2112, 2085}; -- Thaldraszus, Valdrakken, Primalist Future
	[1565] = {1701, 1702, 1703}; -- Ardenweald covenant
	[1533] = {1707, 1708}; -- Bastion Covenant
	[1525] = {1699, 1700}; -- Revendreth Covenant
	[1536] = {1698}; -- Maldraxxus Covenant
}

_V["WQT_ZONE_MAPCOORDS"] = {
		[2276] = WQT_WAR_WITHIN -- Khaz Algar flightmap
		,[2274] = WQT_WAR_WITHIN -- Khaz Algar
		,[2241]	= { -- Emerald Dream flightmap
			[2200] = {["x"] = 0, ["y"] = 0} -- Emerald Dream
		}
		,[2175]	= { -- Zaralek Cavern flightmap
			[2133] = {["x"] = 0, ["y"] = 0} -- Zaralek Cavern
		}
		,[2057] = WQT_DRAGONFLIGHT -- Dragonflight flightmap
		,[1978] = WQT_DRAGONFLIGHT -- Dragonflight
		,[1647] = WQT_SHADOWLANDS -- Shadowlands flightmap
		,[1550]	= WQT_SHADOWLANDS -- Shadowlands
		,[875]	= WQT_ZANDALAR -- Zandalar
		,[1011]	= WQT_ZANDALAR -- Zandalar flightmap
		,[876]	= WQT_KULTIRAS -- Kul Tiras
		,[1014]	= WQT_KULTIRAS -- Kul Tiras flightmap
		,[1504]	= { -- Nazjatar flightmap
			[1355] = {["x"] = 0, ["y"] = 0} -- Nazjatar
		}
		,[905] 	= WQT_LEGION_ARGUS -- Argus
		,[619] 	= WQT_LEGION 
		,[993] 	= WQT_LEGION -- Flightmap	
		,[12] 	= WQT_KALIMDOR 
		,[1209] = WQT_KALIMDOR -- Flightmap
		,[13]	= WQT_EASTERN_KINGDOMS
		,[1208]	= WQT_EASTERN_KINGDOMS -- Flightmap
		,[101]	= WQT_OUTLAND
		,[1467]	= WQT_OUTLAND -- Flightmap
		,[113]	= WQT_NORTHREND 
		,[1384]	= WQT_NORTHREND  -- Flightmap
		,[424]	= WQT_PANDARIA
		,[989]	= WQT_PANDARIA -- Flightmap
		,[572]	= WQT_DRAENOR
		,[990]	= WQT_DRAENOR -- Flightmap
		,[224]	= { -- Stranglethorn Vale
			[210] = {["x"] = 0.42, ["y"] = 0.62} -- Cape
			,[50] = {["x"] = 0.67, ["y"] = 0.40} -- North
		}
		,[947]	= { -- All of Azeroth (Also look at UpdateAzerothZones() in Dataprovider.lua)
			[12] = {["x"] = 0.24, ["y"] = 0.55}
			,[13] = {["x"] = 0.89, ["y"] = 0.52}
			,[113] = {["x"] = 0.49, ["y"] = 0.12}
			,[424] = {["x"] = 0.48, ["y"] = 0.82}
			,[619] = {["x"] = 0.58, ["y"] = 0.39}
			,[875] = {["x"] = 0.54, ["y"] = 0.63}
			,[876] = {["x"] = 0.71, ["y"] = 0.50}
			,[1978] = {["x"] = 0.77, ["y"] = 0.22}
		}
	}

_V["WQT_NO_FACTION_DATA"] = { ["expansion"] = 0 ,["playerFaction"] = nil ,["texture"] = 1103069, ["name"]=_L["NO_FACTION"] } -- No faction
_V["WQT_FACTION_DATA"] = {
	[67] = 		{ ["expansion"] = LE_EXPANSION_CLASSIC ,["playerFaction"] = nil ,["texture"] = 2203914 } -- Horde
	,[469] = 	{ ["expansion"] = LE_EXPANSION_CLASSIC ,["playerFaction"] = nil ,["texture"] = 2203912 } -- Alliance
	,[609] = 	{ ["expansion"] = LE_EXPANSION_CLASSIC ,["playerFaction"] = nil ,["texture"] = 1396983 } -- Cenarion Circle - Call of the Scarab
	,[910] = 	{ ["expansion"] = LE_EXPANSION_CLASSIC ,["playerFaction"] = nil ,["texture"] = 236232 } -- Brood of Nozdormu - Call of the Scarab
	,[1090] = 	{ ["expansion"] = LE_EXPANSION_LEGION ,["playerFaction"] = nil ,["texture"] = 1450997 } -- Kirin Tor
	,[1106] = 	{ ["expansion"] = LE_EXPANSION_CLASSIC ,["playerFaction"] = nil ,["texture"] = 236690 } -- Argent Crusade
	,[1445] = 	{ ["expansion"] = LE_EXPANSION_WARLORDS_OF_DRAENOR ,["playerFaction"] = nil ,["texture"] = 133283 } -- Draenor Frostwolf Orcs
	,[1515] = 	{ ["expansion"] = LE_EXPANSION_WARLORDS_OF_DRAENOR ,["playerFaction"] = nil ,["texture"] = 1002596 } -- Dreanor Arakkoa Outcasts
	,[1731] = 	{ ["expansion"] = LE_EXPANSION_WARLORDS_OF_DRAENOR ,["playerFaction"] = nil ,["texture"] = 1048727 } -- Dreanor Council of Exarchs
	,[1681] = 	{ ["expansion"] = LE_EXPANSION_WARLORDS_OF_DRAENOR ,["playerFaction"] = nil ,["texture"] = 1042727 } -- Dreanor Vol'jin's Spear
	,[1682] = 	{ ["expansion"] = LE_EXPANSION_WARLORDS_OF_DRAENOR ,["playerFaction"] = nil ,["texture"] = 1042294 } -- Dreanor Wrynn's Vanguard
	,[1828] = 	{ ["expansion"] = LE_EXPANSION_LEGION ,["playerFaction"] = nil ,["texture"] = 1450996 } -- Highmountain Tribes
	,[1859] = 	{ ["expansion"] = LE_EXPANSION_LEGION ,["playerFaction"] = nil ,["texture"] = 1450998 } -- Nightfallen
	,[1883] = 	{ ["expansion"] = LE_EXPANSION_LEGION ,["playerFaction"] = nil ,["texture"] = 1450995 } -- Dreamweavers
	,[1894] = 	{ ["expansion"] = LE_EXPANSION_LEGION ,["playerFaction"] = nil ,["texture"] = 1451000 } -- Wardens
	,[1900] = 	{ ["expansion"] = LE_EXPANSION_LEGION ,["playerFaction"] = nil ,["texture"] = 1450994 } -- Court of Farnodis
	,[1948] = 	{ ["expansion"] = LE_EXPANSION_LEGION ,["playerFaction"] = nil ,["texture"] = 1450999 } -- Valarjar
	,[2045] = 	{ ["expansion"] = LE_EXPANSION_LEGION ,["playerFaction"] = nil ,["texture"] = 1708507 } -- Legionfall
	,[2103] = 	{ ["expansion"] = LE_EXPANSION_BATTLE_FOR_AZEROTH ,["playerFaction"] = "Horde" ,["texture"] = 2058217 } -- Zandalari Empire
	,[2165] = 	{ ["expansion"] = LE_EXPANSION_LEGION ,["playerFaction"] = nil ,["texture"] = 1708506 } -- Army of the Light
	,[2170] = 	{ ["expansion"] = LE_EXPANSION_LEGION ,["playerFaction"] = nil ,["texture"] = 1708505 } -- Argussian Reach
	,[2156] = 	{ ["expansion"] = LE_EXPANSION_BATTLE_FOR_AZEROTH ,["playerFaction"] = "Horde" ,["texture"] = 2058211 } -- Talanji's Expedition
	,[2157] = 	{ ["expansion"] = LE_EXPANSION_BATTLE_FOR_AZEROTH ,["playerFaction"] = "Horde" ,["texture"] = 2058207 } -- The Honorbound
	,[2158] = 	{ ["expansion"] = LE_EXPANSION_BATTLE_FOR_AZEROTH ,["playerFaction"] = "Horde" ,["texture"] = 2058213 } -- Voldunai
	,[2159] = 	{ ["expansion"] = LE_EXPANSION_BATTLE_FOR_AZEROTH ,["playerFaction"] = "Alliance" ,["texture"] = 2058204 } -- 7th Legion
	,[2160] = 	{ ["expansion"] = LE_EXPANSION_BATTLE_FOR_AZEROTH ,["playerFaction"] = "Alliance" ,["texture"] = 2058209 } -- Proudmoore Admirality
	,[2161] = 	{ ["expansion"] = LE_EXPANSION_BATTLE_FOR_AZEROTH ,["playerFaction"] = "Alliance" ,["texture"] = 2058208 } -- Order of Embers
	,[2162] = 	{ ["expansion"] = LE_EXPANSION_BATTLE_FOR_AZEROTH ,["playerFaction"] = "Alliance" ,["texture"] = 2058210 } -- Storm's Wake
	,[2163] = 	{ ["expansion"] = LE_EXPANSION_BATTLE_FOR_AZEROTH ,["playerFaction"] = nil ,["texture"] = 2058212 } -- Tortollan Seekers
	,[2164] = 	{ ["expansion"] = LE_EXPANSION_BATTLE_FOR_AZEROTH ,["playerFaction"] = nil ,["texture"] = 2058205 } -- Champions of Azeroth
	,[2373] = 	{ ["expansion"] = LE_EXPANSION_BATTLE_FOR_AZEROTH ,["playerFaction"] = "Horde" ,["texture"] = 2909044 } -- Unshackled
	,[2391] = 	{ ["expansion"] = LE_EXPANSION_BATTLE_FOR_AZEROTH ,["playerFaction"] = nil ,["texture"] = 2909316 } -- Rustbolt
	,[2400] = 	{ ["expansion"] = LE_EXPANSION_BATTLE_FOR_AZEROTH ,["playerFaction"] = "Alliance" ,["texture"] = 2909043 } -- Waveblade Ankoan
	,[2417] = 	{ ["expansion"] = LE_EXPANSION_BATTLE_FOR_AZEROTH ,["playerFaction"] = nil ,["texture"] = 3196264 } -- Uldum Accord
	,[2415] = 	{ ["expansion"] = LE_EXPANSION_BATTLE_FOR_AZEROTH ,["playerFaction"] = nil ,["texture"] = 3196265 } -- Rajani
	-- Shadowlands
	,[2407] =	{ ["expansion"] = LE_EXPANSION_SHADOWLANDS,["playerFaction"] = nil ,["texture"] = 3257748 } -- The Ascended
	,[2410] =	{ ["expansion"] = LE_EXPANSION_SHADOWLANDS,["playerFaction"] = nil ,["texture"] = 3641396 } -- The Undying Army
	,[2413] =	{ ["expansion"] = LE_EXPANSION_SHADOWLANDS,["playerFaction"] = nil ,["texture"] = 3257751 } -- Court of Harvesters
	,[2465] =	{ ["expansion"] = LE_EXPANSION_SHADOWLANDS,["playerFaction"] = nil ,["texture"] = 3641394 } -- The Wild Hunt
	,[2432] =	{ ["expansion"] = LE_EXPANSION_SHADOWLANDS,["playerFaction"] = nil ,["texture"] = 3729461 } -- Ve'nari
	,[2470] =	{ ["expansion"] = LE_EXPANSION_SHADOWLANDS,["playerFaction"] = nil ,["texture"] = 4083292 } -- Korthia
	,[2472] =	{ ["expansion"] = LE_EXPANSION_SHADOWLANDS,["playerFaction"] = nil ,["texture"] = 4067928 } -- Korthia Codex
	,[2478] =	{ ["expansion"] = LE_EXPANSION_SHADOWLANDS,["playerFaction"] = nil ,["texture"] = 4226232 } -- Zereth Mortis
	-- LE_EXPANSION_DRAGONFLIGHT
	,[2507] =	{ ["expansion"] = LE_EXPANSION_DRAGONFLIGHT,["playerFaction"] = nil ,["texture"] = 4687628 } -- Dragonscale Expedition
	,[2511] =	{ ["expansion"] = LE_EXPANSION_DRAGONFLIGHT,["playerFaction"] = nil ,["texture"] = 4687629 } -- Iskaara Tuskarr
	,[2503] =	{ ["expansion"] = LE_EXPANSION_DRAGONFLIGHT,["playerFaction"] = nil ,["texture"] = 4687627 } -- Maruuk Centaur
	,[2510] =	{ ["expansion"] = LE_EXPANSION_DRAGONFLIGHT,["playerFaction"] = nil ,["texture"] = 4687630 } -- Valdrakken Accord
	,[2544] =	{ ["expansion"] = LE_EXPANSION_DRAGONFLIGHT,["playerFaction"] = nil ,["texture"] = 4548878 } -- Artisan's Consortium
	,[2517] =	{ ["expansion"] = LE_EXPANSION_DRAGONFLIGHT,["playerFaction"] = nil ,["texture"] = 4640487 } -- Wrathion
	,[2518] =	{ ["expansion"] = LE_EXPANSION_DRAGONFLIGHT,["playerFaction"] = nil ,["texture"] = 4640488 } -- Sabellian
	,[2550] =	{ ["expansion"] = LE_EXPANSION_DRAGONFLIGHT,["playerFaction"] = nil ,["texture"] = 134565 } -- Cobalt Assembly
	,[2523] =	{ ["expansion"] = LE_EXPANSION_DRAGONFLIGHT,["playerFaction"] = nil ,["texture"] = 4528811 } -- Dark Talons
	,[2524] =	{ ["expansion"] = LE_EXPANSION_DRAGONFLIGHT,["playerFaction"] = nil ,["texture"] = 4528812 } -- Obsidian Warders
	,[2526] =	{ ["expansion"] = LE_EXPANSION_DRAGONFLIGHT,["playerFaction"] = nil ,["texture"] = 4901295 } -- Winterpelt Furbolg
	,[2564] =	{ ["expansion"] = LE_EXPANSION_DRAGONFLIGHT,["playerFaction"] = nil ,["texture"] = 5140835 } -- Loamm Niffen
	,[2553] =	{ ["expansion"] = LE_EXPANSION_DRAGONFLIGHT,["playerFaction"] = nil ,["texture"] = 609811 } -- Soridormi
	,[2574] =	{ ["expansion"] = LE_EXPANSION_DRAGONFLIGHT,["playerFaction"] = nil ,["texture"] = 5244643 } -- Dream Wardens
	,[2615] =	{ ["expansion"] = LE_EXPANSION_DRAGONFLIGHT,["playerFaction"] = nil ,["texture"] = 5315246 } -- Azerothian Archives	
	-- LE_EXPANSION_WAR_WITHIN
	,[2570] =	{ ["expansion"] = LE_EXPANSION_WAR_WITHIN,["playerFaction"] = nil ,["texture"] = 5891368 } -- Hallowfall Arathi
	,[2594] =	{ ["expansion"] = LE_EXPANSION_WAR_WITHIN,["playerFaction"] = nil ,["texture"] = 5891367 } -- The Assembly of the Deeps
	,[2590] =	{ ["expansion"] = LE_EXPANSION_WAR_WITHIN,["playerFaction"] = nil ,["texture"] = 5891369 } -- Council of Dornogal
	,[2600] =	{ ["expansion"] = LE_EXPANSION_WAR_WITHIN,["playerFaction"] = nil ,["texture"] = 5891370 } -- The Severed Threads
	,[2601] =	{ ["expansion"] = LE_EXPANSION_WAR_WITHIN,["playerFaction"] = nil ,["texture"] = 5862764 } -- The Weaver
	--,[2645] =	{ ["expansion"] = LE_EXPANSION_WAR_WITHIN,["playerFaction"] = nil ,["texture"] = 5930319 } -- Earthen
	,[2605] =	{ ["expansion"] = LE_EXPANSION_WAR_WITHIN,["playerFaction"] = nil ,["texture"] = 5862762 } -- The General
	,[2607] =	{ ["expansion"] = LE_EXPANSION_WAR_WITHIN,["playerFaction"] = nil ,["texture"] = 5862763 } -- The Vizier
	,[2640] =	{ ["expansion"] = LE_EXPANSION_WAR_WITHIN,["playerFaction"] = nil ,["texture"] = 5453546 } -- Brann Bronzebeard
}

-- Add localized faction names
for k, v in pairs(_V["WQT_FACTION_DATA"]) do
	local factionData = C_Reputation.GetFactionDataByID(k);
	if factionData ~= nil then
		v.name = factionData.name;
	end
end


_V["WQT_DEFAULTS"] = {
	global = {	
		versionCheck = "";
		updateSeen = false;
		
		["colors"] = {
			["timeCritical"] = RED_FONT_COLOR:GenerateHexColor();
			["timeShort"] = _V["WQT_ORANGE_FONT_COLOR"]:GenerateHexColor();
			["timeMedium"] = _V["WQT_GREEN_FONT_COLOR"]:GenerateHexColor();
			["timeLong"] = _V["WQT_BLUE_FONT_COLOR"]:GenerateHexColor();
			["timeVeryLong"] = _V["WQT_PURPLE_FONT_COLOR"]:GenerateHexColor();
			
			["rewardNone"] = _V["WQT_COLOR_NONE"]:GenerateHexColor();
			["rewardWeapon"] = _V["WQT_COLOR_WEAPON"]:GenerateHexColor();
			["rewardArmor"] = _V["WQT_COLOR_ARMOR"]:GenerateHexColor();
			["rewardConduit"] = _V["WQT_COLOR_RELIC"]:GenerateHexColor();
			["rewardRelic"] = _V["WQT_COLOR_RELIC"]:GenerateHexColor();
			["rewardAnima"] = _V["WQT_COLOR_ARTIFACT"]:GenerateHexColor();
			["rewardArtifact"] = _V["WQT_COLOR_ARTIFACT"]:GenerateHexColor();
			["rewardItem"] = _V["WQT_COLOR_ITEM"]:GenerateHexColor();
			["rewardXp"] = _V["WQT_COLOR_ITEM"]:GenerateHexColor();
			["rewardGold"] = _V["WQT_COLOR_GOLD"]:GenerateHexColor();
			["rewardCurrency"] = _V["WQT_COLOR_CURRENCY"]:GenerateHexColor();
			["rewardHonor"] = _V["WQT_COLOR_HONOR"]:GenerateHexColor();
			["rewardReputation"] = _V["WQT_COLOR_CURRENCY"]:GenerateHexColor();
			["rewardMissing"] = _V["WQT_COLOR_MISSING"]:GenerateHexColor();
			
			["rewardTextWeapon"] = _V["WQT_COLOR_WEAPON"]:GenerateHexColor();
			["rewardTextArmor"] = _V["WQT_COLOR_ARMOR"]:GenerateHexColor();
			["rewardTextConduit"] = WHITE_FONT_COLOR:GenerateHexColor();
			["rewardTextRelic"] = WHITE_FONT_COLOR:GenerateHexColor();
			["rewardTextAnima"] = GREEN_FONT_COLOR:GenerateHexColor();
			["rewardTextArtifact"] = GREEN_FONT_COLOR:GenerateHexColor();
			["rewardTextItem"] = WHITE_FONT_COLOR:GenerateHexColor();
			["rewardTextXp"] = WHITE_FONT_COLOR:GenerateHexColor();
			["rewardTextGold"] = WHITE_FONT_COLOR:GenerateHexColor();
			["rewardTextCurrency"] = WHITE_FONT_COLOR:GenerateHexColor();
			["rewardTextHonor"] = WHITE_FONT_COLOR:GenerateHexColor();
			["rewardTextReputation"] = WHITE_FONT_COLOR:GenerateHexColor();
		};
		
		["general"] = {
			sortBy = 1;
			fullScreenButtonPos = {["anchor"] = "TOPRIGHT", ["x"] = -2, ["y"] = -35};
			fullScreenContainerPos = {["anchor"] = "TOPLEFT", ["x"] = 0, ["y"] = -25};
		
			defaultTab = false;
			saveFilters = true;
			preciseFilters = false;
			emissaryOnly = false;
			useLFGButtons = false;
			autoEmissary = true;
			questCounter = true;
			bountyCounter = true;
			bountyReward = false;
			bountySelectedOnly = true;
			showDisliked = true;
			df_goldPurses = false;
			sl_callingsBoard = true;
			sl_genericAnimaIcons = false;
			
			filterPasses = {
				["calling"] = true;
				["threat"] = true,
				["combatAlly"] = true,
			};
			dislikedQuests = {};
			
			loadUtilities = true;
			
			useTomTom = true;
			TomTomAutoArrow = true;
			TomTomArrowOnClick = false;
		};
		
		["list"] = {
			typeIcon = true;
			factionIcon = true;
			showZone = true;
			amountColors = true;
			alwaysAllQuests = false;
			includeDaily = true;
			colorTime = true;
			fullTime = false;
			rewardNumDisplay = 1;
		};

		["pin"] = {
			-- Mini icons
			typeIcon = true;
			numRewardIcons = 0;
			rarityIcon = false;
			timeIcon = false;
			continentVisible = _V["ENUM_PIN_CONTINENT"].none;
			zoneVisible = _V["ENUM_PIN_ZONE"].all;
			
			filterPoI = true;
			scale = 1;
			disablePoI = false;
			optionalLabel = 1;
			continentPins = false;
			fadeOnPing = true;
			eliteRing = false;
			ringType = _V["RING_TYPES"].time;
			centerType = _V["PIN_CENTER_TYPES"].reward;
			showWarbandBonus = true;
		};

		["filters"] = {
				[_V["FILTER_TYPES"].faction] = {["name"] = FACTION
						,["misc"] = {["none"] = true, ["other"] = true}, ["flags"] = {}}-- Faction filters are assigned later
				,[_V["FILTER_TYPES"].type] = {["name"] = TYPE
						, ["flags"] = {["Default"] = true, ["Elite"] = true, ["PvP"] = true, ["Petbattle"] = true, ["Dungeon"] = true, ["Raid"] = true, ["Profession"] = true, ["Invasion"] = true, ["Assault"] = true, ["Daily"] = true, ["Threat"] = true, ["Bonus"] = true, ["Skyriding"] = true}}
				,[_V["FILTER_TYPES"].reward] = {["name"] = REWARD
						, ["flags"] = {["Item"] = true, ["Armor"] = true, ["Gold"] = true, ["Currency"] = true, ["Anima"] = true, ["Conduits"] = true, ["Artifact"] = true, ["Relic"] = true, ["None"] = true, ["Experience"] = true, ["Honor"] = true, ["Reputation"] = true}}
			};
			
		["profiles"] = {
			
		};
	}
}

for k, v in pairs(_V["WQT_FACTION_DATA"]) do
	if v.expansion >= LE_EXPANSION_LEGION then
		_V["WQT_DEFAULTS"].global.filters[1].flags[k] = true;
	end
end

-- This is just easier to maintain than changing the entire string every time
_V["PATCH_NOTES"] = {
		{["version"] = "11.0.7.1",
			["new"] = {
				"Added Siren Isle.",
			},
			["fixes"] = {
				"Fixed error with incompatible utilities AddOn.",
			},
			["changes"] = {
				"Testing a change in how world quests are hidden or shown. Active world quest pin should be visible now...",
			},
		},
		{["version"] = "11.0.7",
			["intro"] = { "Update for 11.0.7." },
		},
		{["version"] = "11.0.5.3",
			["fixes"] = {
				"Fixed an error using the new optional label option.",
			},
		},
		{["version"] = "11.0.5.2",
			["fixes"] = {
				"Fixed messy display of Vol'dun world quests (again).",
			},
		},
		{["version"] = "11.0.5.1",
			["new"] = {
				"Added new pin option to show a label with reward amounts (gold, item level, reputation, etc).",
			},
			["changes"] = {
				"Moved close button.",
			},
		},
		{["version"] = "11.0.5",
			["intro"] = { "Update for 11.0.5" },
			["fixes"] = {
				"Fixed alot of lua errors.",
			},
		},
		{["version"] = "11.0.2.13",
			["fixes"] = {
				"World quests of City of Threads on Azj-Kahet now displays correctly.",
				"Bonus world quests are now fully working.",
			},
		},
		{["version"] = "11.0.2.12",
			["fixes"] = {
				"Current world quest was not showing on map.",
			},
		},
		{["version"] = "11.0.2.11",
			["fixes"] = {
				"Now World Map filters work correctly and updates WorldQuestTab filters. Should fix some quests that were displayed as world quests.",
				"Pet battles filter now working as intended.",
				"Added missing Skyriding filter option.",
			},
		},
		{["version"] = "11.0.2.10",
			["changes"] = {
				"Disabled WorldQuestTabUtilities, it is not compatible.",
				"Now some settings are easier to click.",
			},
		},
		{["version"] = "11.0.2.9",
			["new"] = {
				"Added option to show Warband bonus icon on the map pin and quest list.",
			},
			["fixes"] = {
				"Fixed flight map showing incorrectly.",
				"Fixed tooltips not showing Warband bonuses.",
			},
		},
		{["version"] = "11.0.2.8",
			["new"] = {
				"Added option to align the world map button to the top right alongside the default ones (\"Map Legend\", \"Map Pin\", \"Map Filter\").",
			},
		},
		{["version"] = "11.0.2.7",
			["fixes"] = {
				"Fixed fullscreen worldmap panel.",
				"Fixed glitch when clicking the \"Map legend\" button.",
			},
		},
		{["version"] = "11.0.2.6",
			["changes"] = {
				"Updated sliders on Settings.",
			},
		},
		{["version"] = "11.0.2.5",
			["changes"] = {
				"\"Settings\" and \"What's new\" panels now uses new scrollbars.",
				"New Headers and Subheaders textures in Settings.",
			},
		},
		{["version"] = "11.0.2.4",
			["new"] ={
				"Added faction based map pin icon type to settings (Map Pins -> Main Icon Type).",
			},
			["fixes"] = {
				"Error when talking to a flight master.",
				"LFG button on world quests now works as intended.",
				"Some boss icons were missing.",
			},
		},
		{["version"] = "11.0.2.3",
			["fixes"] = {
				"Scrollbar now mantains its position.",
			},
		},
		{["version"] = "11.0.2.2",
			["fixes"] = {
				"Trying to fix emissaries functions.",
			},
		},
		{["version"] = "11.0.2.1",
			["changes"] = {
				"Setting's dropdowns now look like the ones on the \"Options\" panel.",
			},
			["fixes"] = {
				"Profiles now work again.",
			},
		},
		{["version"] = "11.0.2",
			["intro"] = { "Update for 11.0.2" },
			["new"] ={
				"Updated to The War Within prepatch 11.0.2.",
			},
			["fixes"] = {
				"Currency and rewards not displaying correctly.",
				"Fixed TomTom context menu.",
				"Move to new compatible APIs for quests.",
			},
			["changes"] = {
				"New UI.",
				"Removed AddonDropdown and use WoW APIs for contextmenu and dropdowns.",
			},
		},
		{["version"] = "10.2.5.0",
			["intro"] = { "Update for 10.2.5." },
			["new"] ={
				"Added new Dragonflight factions.",
			},
		},
		{["version"] = "10.2.0.0",
			["intro"] = { "Update for 10.2.0." },
			["new"] ={
				"Added new Dragonflight zones and factions.",
			},
			["fixes"] = {
				"Updated embedded libraries.",
				"Minor fixes.",
			},
		},
		{["version"] = "10.1.7.0",
			["intro"] = { "Update for 10.1.7." },
			["new"] ={
				"Added option to treat Dragonflight dragon racer's purse rewards as gold.",
			},
		},
		{["version"] = "10.1.5.0",
			["intro"] = { "Update for 10.1.5." },
			["changes"] = {
				"Added experimental zhCN translation.",
			},
			["fixes"] = {
				"Updated embedded libraries.",
			},
		},
		{["version"] = "10.1.0.0",
			["intro"] = { "Update for 10.1.0 content." },
			["new"] ={
				"Added new Dragonflight zones and factions.",
			},
			["fixes"] = {
				'Fixed WQs filtering.',
			},
			["changes"] = {
				"Moved full screen button default position.",
			},
		},
		{["version"] = "10.0.7.1",
			["fixes"] = {
				[[Fixed "Vol'dun" bug.]],
				'Fixed "Elite Ring" size.',
			},
		},
		{["version"] = "10.0.7.0",
			["new"] ={
				"Added new Dragonflight zones and factions.",
			},
			["fixes"] = {
				'Fixed "Anima" translation.',
				'Fixed "Shadowlands" submenu in filters dropdown.',
			},
		},
		{["version"] = "10.0.2.2",
			["fixes"] = {
				'Fixed "Sparks of Life" bug.',
			},
		},
		{["version"] = "10.0.2.1",
			["fixes"] = {
				'Fixed "ShouldHighlightInfo" bug.',
				'Fixed LFG List anchoring to improve compatibility.',
			},
		},
		{["version"] = "10.0.2.0",
			["intro"] = { "Update for 10.0.2 content." },
			["new"] ={
				"Added Dragonflight zones and factions.",
			},
			["fixes"] = {
				"Updated embedded libraries.",
				"Fixed missing zones and factions.",
				"Fixed missing icons.",
			},
		},
		{["version"] = "9.1.01",
			["intro"] = { "Update for 9.1 content." },
			["changes"] = {
				"Changed the calling board progress icons to a texture that looks better at their small scale.",
			},
		},
		{["version"] = "9.0.08",
			["minor"] = "2",
			["fixes"] = {
				"Fixed an error for those also running TomTom.",
			},
		},
		{["version"] = "9.0.08",
			["new"] ={
				"New filter 'Ignores Filters': Allows special quest types such as Callings and Threat quests to ignore filters settings and always show (if they would show in the list otherwise)"
			},
			["changes"] = {
				"Calling quests now have their own icon in the quest list and mini icons for pins. When using Blizzard pin icons, pins for callings will now also have a blue inner circle.",
				"Tooltips rewarding currency and an item will now show everything. In other words, callings will now show if they'll reward an Emblem of Renown.",
				"Quests will now sort their rewards by quality over type. As an example, callings will prioritize showing the Emblem of Renown over the loot container.",
				"Some minor tooltip tweaks both in terms of functionality and information.",
			},
			["fixes"] = {
				"Fixed some missing info in tooltips on the callings board.",
			},
		},
		{["version"] = "9.0.07",
			["intro"] = { "9.0.5 compatibility and fixes." },
			["fixes"] = {
				"Fixed the calling board always showing as Necrolord rather than the player's covenant.",
				"Fixed pin highlights lagging behind when the world quest tab isn't visible.",
			},
		},
		{["version"] = "9.0.06",
			["minor"] = "3 (beta)",
			["changes"] = {
				"Callings on the callings board with either a progress bar or a high number objective will now be displayed as a progress bar instead.",
			},
			["fixes"] = {
				"Clicking a world quest will now correctly set it as the currently tracked quest.",
				"Fixed TomTom settings not showing up for those using the add-on.",
				"Fixed an error that could happen using a wormhole generation. (Maybe?)",
				"Potentially fixed a couple of other errors."
			},
		},
		{["version"] = "9.0.06",
			["minor"] = 2,
			["fixes"] = {
				"Fixed an error related to the LFG buttons setting.",
			},
		},
		{["version"] = "9.0.06",
			["new"] ={
				"Added the option to mark quests as 'uninterested'. You (un)mark a quest as uninterested either by shift-right clicking or through the right click menu. Uninterested quests will be placed at the bottom of the list and become less visible.",
				"Added a 'Uninterested' filter. Take a guess what it does.",
				"Added custom color settings allowing you to change most of the add-on specific colors to your liking.",
			},
			["changes"] = {
				"Mini icons for conduits will now match their type (Finesse, Potency, or Endurance).",
				"The quest list should no longer jump back to the top when it gets updated. Finally... that's been bugging me for ages.",
				"Moved filters related to older content to their own sub menus.",
				"You can now control right click a quest to place the waypoint at its location.",
				"Added tooltips to the right-click menu to inform about shortcuts.",
			},
			["fixes"] = {
				"Improved memory usage in different parts of the add-on.",
				"Fixed an issue that could cause duplicate callings to show up on the calling board or not callings to show up at all.",
				"Fixed an issue with shift-clicking to track quests.",
				"Fixed quests in covenant areas not being included on some maps.",
				"Fixed the entire quest frame disappearing when untracking a quest while quest details are shown.",
				"Focusing on a calling will no longer hide relevant world quests. (Doesn't apply when the map is in full screen mode)",
			},
		},
		{["version"] = "9.0.05",
			["minor"] = 2,
			["fixes"] = {
				"Fixed an error that would happen for those that have the 'alwaysCompareItems' cvar set to 1.",
			},
		},
		{["version"] = "9.0.05",
			["new"] = {
				"Added a callings board to the world map similar to the ones in Legion and BfA. This is enabled by default but can be turned off in the settings.",
				"Conduits are now their own reward type which includes filtering and reward displays in the quest list.",
			},
			["changes"] = {
				"Replaced all covenant factions icons to their covenant sigil and added an icon for Ve'nari.",
				"Moved some of the settings around so the ones relevant to older content are out of the way.",
				"Subcategories in settings can now also be expanded and collapsed.",
			},
			["fixes"] = {
				"Fixed the quest log disappearing when changing maps while quest details are open.",
				"Fixed a potential error when right clicking a world quest.",
				"Fixed some tainting issues should prevent combat errors.",
			},
		},
		{["version"] = "9.0.04",
			["minor"] = "0 (beta)",
			["new"] = {
				"Anima is now it's own reward type and should show the total anima rather than number of tokens.",
			},
			["fixes"] = {
				"Fixed Shadowlands world quests not showing up at flight masters.",
				"Fixed an error related to covenant callings.",
				"Fixed an issue where disabled filters wouldn't show tooltips.",
			},
		},
		{["version"] = "9.0.03",
			["fixes"] = {
				"Fixed default icon for factions which don't have a designated icon yet.",
				"Fixed a quest detail issue with ElvUI.",
				"Fixed one of the Shadowlands factions having switched IDs.",
			},
		},
		{["version"] = "9.0.02",
			["new"] = {
				"New map pin option: Zone Map Pins (default All). Which quests should be allowed to show map pins on zone maps. (None, Tracked, or All)",
				"New map pin option: Continent Map Pins (default None). Which quests should be allowed to show map pins on continent maps. (None, Tracked, or All)",
			},
			["changes"] = {
				"The 'Pins On Continent' setting has been replaced by the new 'Continent Map Pins'. Its value has been transfered over.",
				"Moved the settings and 'What's new' options from the filters to a separate button.",
			},
			["fixes"] = {
				"Fixed Ally Quests in Nazjatar not showing the daily quest icon on their map pins.",
				"Fixed the missing backdrop in the debug dump window.",
				"'Fixed' the quest log counter.",
				"Fixed an error that could occur when trying to right-click certain quests.",
				"Fixed flickering of the quest list background when it's being reloaded",
				"Fixed being able to add daily quests to the quest watch list, as the official API doesn't support them.",
			},
		},
		{["version"] = "9.0.01",
			["intro"] = {"Update for the new 9.0 UI."},
			["new"] = {
				"New type filter: Bonus. Filters out what the game considers bonus quests.",
				"New general option: Emissary Reward Icon (default off). Adds an icon to the emissary tabs indicating the type of reward it offers.",
				"New general option: Selected Emissary Only (default on). Only mark quests for the currently selected emissary. Turning this off will instead mark quests for any of the active emissaries.",
				"Right clicking a quest now includes an option to place the new official map pin at the quest's location.",
			},
			["changes"] = {
				"Moved the TomTom waypoint option to the bottom of the right click menu.",
			},
			["fixes"] = {
				"Fixed map pin visuals for quests with no rewards.",
			},
		},
	}
	
_V["LATEST_UPDATE"] = "";
	
function _V:GeneratePatchNotes()
	_V["LATEST_UPDATE"] =  WQT_Utils:FormatPatchNotes(_V["PATCH_NOTES"], "World Quest Tab");
	_DeepWipeTable(_V["PATCH_NOTES"]);
end
