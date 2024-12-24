--
-- Info structure
--
-- questID					[number] questID
-- isAllyQuest				[boolean] is a quest for combat allies (Nazjatar)
-- isDaily					[boolean] is a daily type quest (Nazjatar & threat quests)
-- isCriteria				[boolean] is part of currently selected emissary
-- alwaysHide				[boolean] If the quest should be hidden no matter what
-- passedFilter				[boolean] passed current filters
-- isValid					[boolean] true if the quest is valid. Quest are invalid when they are missing quest data
-- time						[table] time related values
--		seconds					[number] seconds remaining when the data was gathered (To check the difference between no time and expired time)
-- mapInfo					[table] zone related values, for more accurate position use WQT_Utils:GetQuestMapLocation
--		mapX					[number] x pin position
--		mapY					[number] y pin position
-- Reward					[table]
--		typeBits				[bitfield] a combination of flags for all the types of rewards the quest provides. I.e. AP + gold + rep = 2^3 + 2^6 + 2^9 = 584 (1001001000‬)
-- rewardList				[table] List of rewards sorted by priority and filter settings
--		iterative list of rewardInfo tables
--
-- questInfo Functions
-- 
-- GetRewardType()			Type of the top reward
-- GetRewardId()			Id of the top reward
-- GetRewardAmount()		Amount of the top reward
-- GetRewardTexture()		Texture of the top reward
-- GetRewardQuality()		Quality of the top reward
-- GetRewardColor()			Color of the top reward
-- GetRewardCanUpgrade()	If the top reward has a chance of upgrading
-- TryDressUpReward()		Try all of the rewards to be shown in the dressing room
-- IsExpired()				Whether the quest time is expired or not
-- GetReward(index)			Get a specific reward from the list. nil if index is not available
-- IterateRewards()			Return ipairs of the rewards

-- RewardInfo structure
--
--	type					[number] type of reward. See WQT_REWARDTYPE in Data.lua
--	texture					[number/string] texture of the reward. can be string for things like gold or unknown reward
--	amount					[amount] amount of items, gold, rep, or item level
--	id						[number] itemId for reward. 0 if not applicable (i.e. gold)
--	quality					[number] item quality; common, rare, epic, etc
--	canUpgrade				[boolean, nullable] true if item has a chance to upgrade (e.g. ilvl 285+)
--	color					[Color] color based on the type of reward

--
-- For other data use following functions
--
-- local title, factionId = C_TaskQuest.GetQuestInfoByQuestID(questID);
-- local mapInfo = WQT_Utils:GetCachedMapInfo(zoneId); 	| mapInfo = {[mapID] = number, [name] = string, [parenMapID] = number, [mapType] = Enum.UIMapType};
-- local mapInfo = WQT_Utils:GetMapInfoForQuest(questID); 	| Quick function that gets the zoneId from the questID first
-- local factionInfo = WQT_Utils:GetFactionDataInternal(factionId); 	| factionInfo = {[name] = string, [texture] = string/number, [playerFaction] = string, [expansion] = number}
-- local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex, displayTimeLeft = GetQuestTagInfo(questID);
-- local texture, sizeX, sizeY = WQT_Utils:GetCachedTypeIconData(worldQuestType, tradeskillLineIndex);
-- local timeLeftSeconds, timeString, color, timeStringShort, category = WQT_Utils:GetQuestTimeString(questInfo, fullString, unabreviated);
-- local x, y = WQT_Utils:GetQuestMapLocation(questID, mapId); | More up to date position than mapInfo

--
-- Callbacks (WQT_WorldQuestFrame:RegisterCallback(event, func, addonName))
--
-- "InitFilter" 			(self, level) After InitFilter finishes
-- "InitSettings"			(self, level) After InitSettings finishes
-- "DisplayQuestList" 		(skipPins) After all buttons in the list have been updated
-- "FilterQuestList"		() After the list has been filtered
-- "UpdateQuestList"		() After the list has been both filtered and updated
-- "QuestsLoaded"			() After the dataprovider updated its quest data
-- "WaitingRoomUpdated"		() After data in the dataprovider's waitingroom got updated
-- "SortChanged"			(category) After sort category was changed to a different one
-- "ListButtonUpdate"		(button) After a button was updated and shown
-- "AnchorChanged"			(anchor) After the anchor of the quest list has changed
-- "MapPinInitialized"		(pin) After a map pin has been fully setup to be shown
-- "WorldQuestCompleted"	(questID, questInfo) When a world quest is completed. questInfo gets cleared shortly after this callback is triggered

local addonName, addon = ...

local WQT = addon.WQT;

local _L = addon.L
local _V = addon.variables;
local WQT_Utils = addon.WQT_Utils;
local WQT_Profiles = addon.WQT_Profiles;

local _; -- local trash 
local _emptyTable = {};

local _playerFaction = GetPlayerFactionGroup();
local _playerName = UnitName("player");

local utilitiesStatus = select(5, C_AddOns.GetAddOnInfo("WorldQuestTabUtilities"));
local _utilitiesInstalled = not utilitiesStatus or utilitiesStatus ~= "MISSING";

local _WFMLoaded = C_AddOns.IsAddOnLoaded("WorldFlightMap");

-- Custom number abbreviation to fit inside reward icons in the list.
local function GetLocalizedAbbreviatedNumber(number)
	if type(number) ~= "number" then return "NaN" end;

	local intervals = _L["IS_AZIAN_CLIENT"] and _V["NUMBER_ABBREVIATIONS_ASIAN"] or _V["NUMBER_ABBREVIATIONS"];
	
	for i = 1, #intervals do
		local interval = intervals[i];
		local value = interval.value;
		local valueDivTen = value / 10;
		if (number >= value) then
			if (interval.decimal) then
				local rest = number - floor(number/value)*value;
				if (rest < valueDivTen) then
					return interval.format:format(floor(number/value));
				else
					return interval.format:format(floor(number/valueDivTen)/10);
				end
			end
			return interval.format:format(floor(number/valueDivTen));
		end
	end
	
	return number;
end

local function slashcmd(msg)
	if (msg == "debug") then
		addon.debug = not addon.debug;
		WQT_QuestScrollFrame:UpdateQuestList();
		print("WQT: debug", addon.debug and "enabled" or "disabled");
		return;
	elseif (msg:find("^dump")) then
		local addition = msg:sub(6)
		WQT_DebugFrame:DumpDebug(addition);
		return;
	end
end

local function IsRelevantFilter(filterID, key)
	-- Check any filter outside of factions if disabled by worldmap filter
	if (filterID > _V["FILTER_TYPES"].faction) then return not WQT:FilterIsWorldMapDisabled(key) end
	-- Faction filters that are a string get a pass
	if (not key or type(key) == "string") then return true; end
	-- Factions with an ID of which the player faction is matching or neutral pass
	local data = WQT_Utils:GetFactionDataInternal(key);
	if (data and not data.playerFaction or data.playerFaction == _playerFaction) then return true; end
	
	return false;
end


local function WQT_InitFilterDropdown(self)
	-- Show X button if filtering
	self:SetIsDefaultCallback(function()
		return not WQT:IsFiltering();
	end);
	
	-- Set default filters on click
	self:SetDefaultCallback(function()
		WQT_CoreMixin:FilterClearButtonOnClick();
	end);
	
	self:SetupMenu(function(dropdown, rootDescription)
		rootDescription:SetTag("MENU_WQT_FILTER");
				
		-- Faction, reward, and type filters
		for k, v in pairs(WQT.settings.filters) do
			local submenu = rootDescription:CreateButton(v.name);
			
			submenu:CreateButton(CHECK_ALL, function ()
							WQT:SetAllFilterTo(k, true);
							WQT_QuestScrollFrame:UpdateQuestList();
							return MenuResponse.Refresh;
						end, true);
			submenu:CreateButton(UNCHECK_ALL, function()
							WQT:SetAllFilterTo(k, false);
							WQT_QuestScrollFrame:UpdateQuestList();
							return MenuResponse.Refresh;
						end, false);
			-- Factions
			if k ==  _V["FILTER_TYPES"]["faction"] then
				local filter = WQT.settings.filters[_V["FILTER_TYPES"].faction];
				local options = filter.flags;
				local order = WQT.filterOrders[_V["FILTER_TYPES"].faction] 
				local currExp = _V["CURRENT_EXPANSION"];
				
				-- Title of current expansion
				submenu:CreateDivider();
				submenu:CreateTitle(_G["EXPANSION_NAME"..currExp]);
				
				for k, flagKey in pairs(order) do
					local factionInfo = type(flagKey) == "number" and WQT_Utils:GetFactionDataInternal(flagKey) or nil;
					-- Only factions that are current expansion and match the player's faction
					if (factionInfo and factionInfo.expansion == currExp and (not factionInfo.playerFaction or factionInfo.playerFaction == _playerFaction)) then
						submenu:CreateCheckbox(type(flagKey) == "number" and C_Reputation.GetFactionDataByID(flagKey).name or flagKey,
							function()
								return options[flagKey]
							end,
							function()
								options[flagKey] = not options[flagKey];
								WQT_QuestScrollFrame:UpdateQuestList();
							end);
					end
				end
				
				-- Other expansions
				submenu:CreateSpacer();
				local expansionMenu = submenu:CreateButton(EXPANSION_FILTER_TEXT);
				
				-- Dragonflight
				local subexpansionMenu = expansionMenu:CreateButton(EXPANSION_NAME9);
				local options = WQT.settings.filters[1].flags;
				local order = WQT.filterOrders[1] 
				local currExp = LE_EXPANSION_DRAGONFLIGHT;
				for k, flagKey in pairs(order) do
					local factionInfo = type(flagKey) == "number" and WQT_Utils:GetFactionDataInternal(flagKey) or nil;
					if (factionInfo and factionInfo.expansion == currExp and (not factionInfo.playerFaction or factionInfo.playerFaction == _playerFaction)) then
						subexpansionMenu:CreateCheckbox(type(flagKey) == "number" and factionInfo.name or flagKey,
							function()
								return options[flagKey]
							end,
							function()
								options[flagKey] = not options[flagKey];
								if (options[flagKey]) then
									WQT_WorldQuestFrame.pinDataProvider:RefreshAllData()
								end
								WQT_QuestScrollFrame:UpdateQuestList();
							end);		
					end
				end
				
				-- Shadowlands
				subexpansionMenu = expansionMenu:CreateButton(EXPANSION_NAME8);
				options = WQT.settings.filters[1].flags;
				order = WQT.filterOrders[1] 
				currExp = LE_EXPANSION_SHADOWLANDS;
				for k, flagKey in pairs(order) do
					local factionInfo = type(flagKey) == "number" and WQT_Utils:GetFactionDataInternal(flagKey) or nil;
					if (factionInfo and factionInfo.expansion == currExp and (not factionInfo.playerFaction or factionInfo.playerFaction == _playerFaction)) then
						subexpansionMenu:CreateCheckbox(type(flagKey) == "number" and factionInfo.name or flagKey,
							function()
								return options[flagKey]
							end,
							function()
								options[flagKey] = not options[flagKey];
								if (options[flagKey]) then
									WQT_WorldQuestFrame.pinDataProvider:RefreshAllData()
								end
								WQT_QuestScrollFrame:UpdateQuestList();
							end);		
					end
				end
				
				-- BFA
				subexpansionMenu = expansionMenu:CreateButton(EXPANSION_NAME7);
				options = WQT.settings.filters[1].flags;
				order = WQT.filterOrders[1] 
				currExp = LE_EXPANSION_BATTLE_FOR_AZEROTH;
				for k, flagKey in pairs(order) do
					local factionInfo = type(flagKey) == "number" and WQT_Utils:GetFactionDataInternal(flagKey) or nil;
					if (factionInfo and factionInfo.expansion == currExp and (not factionInfo.playerFaction or factionInfo.playerFaction == _playerFaction)) then
						subexpansionMenu:CreateCheckbox(type(flagKey) == "number" and factionInfo.name or flagKey,
							function()
								return options[flagKey]
							end,
							function()
								options[flagKey] = not options[flagKey];
								if (options[flagKey]) then
									WQT_WorldQuestFrame.pinDataProvider:RefreshAllData()
								end
								WQT_QuestScrollFrame:UpdateQuestList();
							end);		
					end
				end
				
				-- Legion
				subexpansionMenu = expansionMenu:CreateButton(EXPANSION_NAME6);
				options = WQT.settings.filters[1].flags;
				order = WQT.filterOrders[1] 
				currExp = LE_EXPANSION_LEGION;
				for k, flagKey in pairs(order) do
					local factionInfo = type(flagKey) == "number" and WQT_Utils:GetFactionDataInternal(flagKey) or nil;
					if (factionInfo and factionInfo.expansion == currExp and (not factionInfo.playerFaction or factionInfo.playerFaction == _playerFaction)) then
						subexpansionMenu:CreateCheckbox(type(flagKey) == "number" and factionInfo.name or flagKey,
							function()
								return options[flagKey]
							end,
							function()
								options[flagKey] = not options[flagKey];
								if (options[flagKey]) then
									WQT_WorldQuestFrame.pinDataProvider:RefreshAllData()
								end
								WQT_QuestScrollFrame:UpdateQuestList();
							end);		
					end
				end
				
			-- Types and rewards
			elseif k == _V["FILTER_TYPES"]["type"] or k == _V["FILTER_TYPES"]["reward"] then
				local value = k;
				local options = WQT.settings.filters[value].flags;
				local order = WQT.filterOrders[value] 
				local haveLabels = (_V["WQT_TYPEFLAG_LABELS"][value] ~= nil);
				local hasOldContent = false;
				for k, flagKey in pairs(order) do
					if (not WQT_Utils:FilterIsOldContent(value, flagKey)) then
						local subsubmenu = submenu:CreateCheckbox(haveLabels and _V["WQT_TYPEFLAG_LABELS"][value][flagKey] or flagKey,
							function()
								return options[flagKey]
							end,
							function()
								options[flagKey] = not options[flagKey];
								WQT_QuestScrollFrame:UpdateQuestList();
							end);
					end
				end
			end
		end

		-- Quests types that ignore filters
		local submenu = rootDescription:CreateButton(_L["IGNORES_FILTERS"]);
		
		-- Callings 
		submenu:CreateCheckbox(CALLINGS_QUESTS, function()
			return WQT.settings.general.filterPasses.calling
		end, function()
			WQT.settings.general.filterPasses.calling = not WQT.settings.general.filterPasses.calling;
			WQT_QuestScrollFrame:UpdateQuestList();
		end);
		
		-- Threat
				submenu:CreateCheckbox(REPORT_THREAT, function()
			return WQT.settings.general.filterPasses.threat
		end, function()
			WQT.settings.general.filterPasses.threat = not WQT.settings.general.filterPasses.threat;
			WQT_QuestScrollFrame:UpdateQuestList();
		end);
		
		-- Uninterested
		rootDescription:CreateCheckbox(_L["UNINTERESTED"], function()
			return WQT.settings.general.showDisliked
		end, function()
			WQT.settings.general.showDisliked = not WQT.settings.general.showDisliked;
		end);
		
		
		-- Emissary only filter
		rootDescription:CreateCheckbox(_L["TYPE_EMISSARY"], function()
			return WQT.settings.general.emissaryOnly;
		end, function()
			WQT.settings.general.emissaryOnly = not WQT.settings.general.emissaryOnly;
			WQT_WorldQuestFrame.autoEmissaryId = nil;
			WQT_QuestScrollFrame:UpdateQuestList();
			
			if not WQT.settings.general.emissaryOnly then
				WQT_WorldQuestFrame.autoEmissaryId = nil;
			end
		end);
		
		
	end);
end

local function WQT_InitSortDropdown(self)
	-- Sort
	self:SetupMenu(function(dropdown, rootDescription)
		rootDescription:SetTag("MENU_WQT_SORT");
		
		for k, option in pairs(_V["WQT_SORT_OPTIONS"]) do
			local submenu = rootDescription:CreateRadio(option,
				function() return k == WQT.settings.general.sortBy; end,
				function(self, category)
					WQT:Sort_OnClick(self, k);
				end, k);
		end
	end);
end

local function WQT_InitSettingsDropdown(self)
	-- Settings
	self:SetupMenu(function(dropdown, rootDescription)
		rootDescription:SetTag("MENU_WQT_SETTINGS");
		
		rootDescription:CreateButton(SETTINGS, function ()
							WQT_WorldQuestFrame:ShowOverlayFrame(WQT_SettingsFrame);
							return;
						end, true);
						
		local newText = WQT.db.global.updateSeen and "" or "|TInterface\\FriendsFrame\\InformationIcon:14|t ";
		rootDescription:CreateButton(newText .. _L["WHATS_NEW"], function()
							local scrollFrame = WQT_VersionFrame;
							local blockerText = scrollFrame.Text;
							
							blockerText:SetText(_V["LATEST_UPDATE"]);
							
							WQT.db.global.updateSeen = true;
							
							WQT_WorldQuestFrame:ShowOverlayFrame(scrollFrame);
							return;
						end, true);
	end);
	
	WQT_WorldQuestFrame:TriggerCallback("InitSettings", self);
end

-- Sort filters alphabetically regardless of localization
local function GetSortedFilterOrder(filterId)
	local filter = WQT.settings.filters[filterId];
	local tbl = {};
	for k, v in pairs(filter.flags) do
		table.insert(tbl, k);
	end
	table.sort(tbl, function(a, b) 
				if (filterId == _V["FILTER_TYPES"].faction) then
					-- Compare 2 factions
					if(type(a) == "number" and type(b) == "number")then
						local _, nameA = C_Reputation.GetFactionDataByID(tonumber(a));
						local _, nameB = C_Reputation.GetFactionDataByID(tonumber(b));
						if nameA and nameB then
							return nameA < nameB;
						end
						return a and not b;
					end
				else
					-- Compare localized labels for tpye and 
					if (_V["WQT_TYPEFLAG_LABELS"][filterId]) then
						return (_V["WQT_TYPEFLAG_LABELS"][filterId][a] or "") < (_V["WQT_TYPEFLAG_LABELS"][filterId][b] or "");
					end
				end
				-- Failsafe
				return tostring(a) < tostring(b);
			end)
	return tbl;
end

local function SortQuestList(a, b, sortID)
	-- Invalid goes to the bottom
	if (not a.isValid or not b.isValid) then
		if (a.isValid == b.isValid) then 
			return a.questID < b.questID;
		end;
		return a.isValid and not b.isValid;
	end
	
	-- Filtered out quests go to the back (for debug view mainly)
	if (not a.passedFilter or not b.passedFilter) then
		if (a.passedFilter == b.passedFilter) then 
			return a.questID < b.questID; 
		end;
		return a.passedFilter and not b.passedFilter;
	end
	
	-- Disliked quests go to the back of the list
	local aDisliked = a:IsDisliked();
	local bDisliked = b:IsDisliked();
	if (aDisliked ~= bDisliked) then 
		return not aDisliked;
	end 

	-- Sort by a list of filters depending on the current filter choice
	local order = _V["SORT_OPTION_ORDER"][sortID];
	if (not order) then
		order = _emptyTable;
		WQT:debugPrint("No sort order for", sortID);
		return a.questID < b.questID;
	end
	
	for k, criteria in ipairs(order) do
		if(_V["SORT_FUNCTIONS"][criteria]) then
			local result = _V["SORT_FUNCTIONS"][criteria](a, b);
			if (result ~= nil) then 
				return result 
			end;
		else
			WQT:debugPrint("Invalid sort criteria", criteria);
		end
	end
	
	-- Worst case fallback
	return a.questID < b.questID;
end

local function GetNewSettingData(old, default)
	return old == nil and default or old;
end

local function ConvertOldSettings(version)
	if (not version or version == "") then
		WQT.db.global.versionCheck = "1";
		-- It's a new user, their settings are perfect
		-- Unless I change my mind again
		return;
	end
	-- BfA
	if (version < "8.0.1") then
		-- In 8.0.01 factions use ids rather than name
		local repFlags = WQT.db.global.filters[1].flags;
		for name in pairs(repFlags) do
			if (type(name) == "string" and name ~= "Other" and name ~= _L["NO_FACTION"]) then
				repFlags[name] = nil;
			end
		end
	end
	-- Pin rework, turn off pin time by default
	if (version < "8.2.01")  then
		WQT.db.global.showPinTime = false;
	end
	-- Reworked save structure
	if (version < "8.2.02")  then
		WQT.db.global.general.defaultTab =		GetNewSettingData(WQT.db.global.defaultTab, false);
		WQT.db.global.general.saveFilters = 		GetNewSettingData(WQT.db.global.saveFilters, true);
		WQT.db.global.general.emissaryOnly = 	GetNewSettingData(WQT.db.global.emissaryOnly, false);
		WQT.db.global.general.useLFGButtons = 	GetNewSettingData(WQT.db.global.useLFGButtons, false);
		WQT.db.global.general.autoEmissary = 	GetNewSettingData(WQT.db.global.autoEmissary, true);
		WQT.db.global.general.questCounter = 	GetNewSettingData(WQT.db.global.questCounter, true);
		WQT.db.global.general.bountyCounter = 	GetNewSettingData(WQT.db.global.bountyCounter, true);
		WQT.db.global.general.useTomTom = 		GetNewSettingData(WQT.db.global.useTomTom, true);
		WQT.db.global.general.TomTomAutoArrow = 	GetNewSettingData(WQT.db.global.TomTomAutoArrow, true);
		
		WQT.db.global.list.typeIcon = 			GetNewSettingData(WQT.db.global.showTypeIcon, true);
		WQT.db.global.list.factionIcon = 		GetNewSettingData(WQT.db.global.showFactionIcon, true);
		WQT.db.global.list.showZone = 			GetNewSettingData(WQT.db.global.listShowZone, true);
		WQT.db.global.list.amountColors = 		GetNewSettingData(WQT.db.global.rewardAmountColors, true);
		WQT.db.global.list.alwaysAllQuests =		GetNewSettingData(WQT.db.global.alwaysAllQuests, false);
		WQT.db.global.list.fullTime = 			GetNewSettingData(WQT.db.global.listFullTime, false);

		WQT.db.global.pin.typeIcon =				GetNewSettingData(WQT.db.global.pinType, true);
		WQT.db.global.pin.rewardTypeIcon =		GetNewSettingData(WQT.db.global.pinRewardType, false);
		WQT.db.global.pin.filterPoI =			GetNewSettingData(WQT.db.global.filterPoI, true);
		WQT.db.global.pin.bigPoI =				GetNewSettingData(WQT.db.global.bigPoI, false);
		WQT.db.global.pin.disablePoI =			GetNewSettingData(WQT.db.global.disablePoI, false);
		WQT.db.global.pin.reward =				GetNewSettingData(WQT.db.global.showPinReward, true);
		WQT.db.global.pin.timeLabel =			GetNewSettingData(WQT.db.global.showPinTime, false);
		WQT.db.global.pin.ringType =				GetNewSettingData(WQT.db.global.ringType, _V["RING_TYPES"].time);
		
		-- Clean up old data
		local version = WQT.db.global.versionCheck;
		local sortBy = WQT.db.global.sortBy;
		local updateSeen = WQT.db.global.updateSeen;
		
		if (WQT.settings) then
			for k, v in pairs(WQT.settings) do
				if (type(v) ~= "table") then
					WQT.settings[k] = nil;
				end
			end
		end
		
		WQT.db.global.versionCheck = version;
		WQT.db.global.sortBy = sortBy;
		WQT.db.global.updateSeen = updateSeen;
	end
	
	if (version < "8.3.01")  then
		WQT.db.global.pin.scale = WQT.db.global.pin.bigPoI and 1.15 or 1;
		WQT.db.global.pin.centerType = WQT.db.global.pin.reward and _V["PIN_CENTER_TYPES"].reward or _V["PIN_CENTER_TYPES"].blizzard;
	end
	
	if (version < "8.3.02")  then
		local factionFlags = WQT.db.global.filters[_V["FILTER_TYPES"].faction].flags;
		-- clear out string keys
		for k in pairs(factionFlags) do
			if (type(k) == "string") then
				factionFlags[k] = nil;
			end
		end
	end
	
	if (version < "8.3.03")  then
		-- Anchoring changed, reset to default position
		if (not WQT.db.global.fullScreenButtonPos) then
			WQT.db.global.fullScreenButtonPos = {};
		end
		WQT.db.global.fullScreenButtonPos.anchor =  _V["WQT_DEFAULTS"].global.general.fullScreenButtonPos.anchor;
		WQT.db.global.fullScreenButtonPos.x = _V["WQT_DEFAULTS"].global.general.fullScreenButtonPos.x;
		WQT.db.global.fullScreenButtonPos.y = _V["WQT_DEFAULTS"].global.general.fullScreenButtonPos.y;
	end
	
	if (version < "8.3.04")  then
		-- Changes for profiles
		if (WQT.db.global.sortBy) then
			WQT.db.global.general.sortBy = WQT.db.global.sortBy;
			WQT.db.global.sortBy = nil;
		end
		if (WQT.db.global.fullScreenButtonPos) then
			WQT.db.global.general.fullScreenButtonPos = WQT.db.global.fullScreenButtonPos;
			WQT.db.global.fullScreenButtonPos = nil;
		end
		if (WQT.db.global.fullScreenContainerPos) then
			WQT.db.global.general.fullScreenContainerPos = WQT.db.global.fullScreenContainerPos;
			WQT.db.global.fullScreenContainerPos = nil;
		end
		
		-- Forgot to clear this in 8.3.01
		WQT.db.global.pin.bigPoI = nil;
		WQT.db.global.pin.reward = nil; 
	end
	
	if (version < "9.0.02") then
		-- More specific options for map pins
		WQT.db.global.pin.continentVisible = WQT.db.global.pin.continentPins and _V["ENUM_PIN_CONTINENT"].all or _V["ENUM_PIN_CONTINENT"].none;
		WQT.db.global.pin.continentPins = nil
	end
	
	if (version < "11.0.2.8") then
		-- Enable warband bonus displays by default
		WQT.db.global.pin.showWarbandBonus = true;
		WQT.db.global.list.showWarbandBonus = true;
	end

	if (version < "11.0.5.1") then
		-- Add new pin option
		WQT.db.global.pin.optionalLabel = _V["OPTIONAL_LABEL_TYPES"].none;
	end
end

-- Display an indicator on the filter if some official map filters might hide quest
function WQT:UpdateFilterIndicator()
	local isFilterUncheck = false;
	for k, cVar in pairs(_V["WQT_CVAR_LIST"]) do
		if C_CVar.GetCVarBool(cVar) == false then
			isFilterUncheck = true;
			break;
		end
	end

	if not isFilterUncheck then
		WQT_WorldQuestFrame.FilterButton.Indicator:Hide();
	else
		WQT_WorldQuestFrame.FilterButton.Indicator:Show();
	end
end

function WQT:SetAllFilterTo(id, value)
	local filter = WQT.settings.filters[id];
	if (not filter) then return end;
	
	local misc = filter.misc;
	if (misc) then
		for k, v in pairs(misc) do
			misc[k] = value;
		end
	end
	
	local flags = filter.flags;
	for k, v in pairs(flags) do
		flags[k] = value;
	end
end

-- Wheter the quest is being filtered because of official map filter settings
function WQT:FilterIsWorldMapDisabled(filter)
	if (filter == "Petbattle" and not C_CVar.GetCVarBool("showTamers")) or (filter == "Artifact" and not C_CVar.GetCVarBool("worldQuestFilterArtifactPower")) or (filter == "Currency" and not C_CVar.GetCVarBool("worldQuestFilterResources"))
		or (filter == "Gold" and not C_CVar.GetCVarBool("worldQuestFilterGold")) or (filter == "Armor" and not C_CVar.GetCVarBool("worldQuestFilterEquipment")) then
		
		return true;
	end

	return false;
end

function WQT:Sort_OnClick(self, category)
	local dropdown = WQT_WorldQuestFrame.SortDropdown;
	if ( category and dropdown.active ~= category ) then
		WQT.settings.general.sortBy = category;
		WQT_QuestScrollFrame:UpdateQuestList();
		WQT_WorldQuestFrame:TriggerCallback("SortChanged", category);
	end
end

function WQT:InitTrackContextMenu(self)
	
	local questInfo = self.questInfo;
	if (not questInfo) then return; end
	
	local questID = questInfo.questID;
	local mapInfo = WQT_Utils:GetMapInfoForQuest(questID);
	local tagInfo = questInfo:GetTagInfo();
	local title = C_TaskQuest.GetQuestInfoByQuestID(questID);
	
	MenuUtil.CreateContextMenu(self, function(owner, rootDescription)
		rootDescription:SetTag("MENU_WQT_TRACK");
		rootDescription:CreateTitle(title);
		
		local button;
		-- Tracking
		if (QuestUtils_IsQuestWatched(questID)) then		
			button = rootDescription:CreateButton(UNTRACK_QUEST, function ()
					C_QuestLog.RemoveWorldQuestWatch(questID);
					if WQT_WorldQuestFrame:GetAlpha() > 0 then 
						WQT_QuestScrollFrame:DisplayQuestList();
					end
				end, true);
		else
			button = rootDescription:CreateButton(TRACK_QUEST, function ()
					C_QuestLog.RemoveWorldQuestWatch(questID);
					C_QuestLog.AddWorldQuestWatch(questID, Enum.QuestWatchType.Manual);
					C_SuperTrack.SetSuperTrackedQuestID(questID);
					if WQT_WorldQuestFrame:GetAlpha() > 0 then 
						WQT_QuestScrollFrame:DisplayQuestList();
					end
				end, true);
		end
		button:SetTooltip(function(tooltip, elementDescription)
			GameTooltip_SetTitle(tooltip, MenuUtil.GetElementText(elementDescription));
			GameTooltip_AddInstructionLine(tooltip, _L["SHORTCUT_TRACK"]);
		end);
		
		-- New 9.0 waypoint system
		button = rootDescription:CreateButton(_L["PLACE_MAP_PIN"], function ()
				questInfo:SetAsWaypoint();
				C_SuperTrack.SetSuperTrackedUserWaypoint(true);
			end, true);
		button:SetTooltip(function(tooltip, elementDescription)
			GameTooltip_SetTitle(tooltip, MenuUtil.GetElementText(elementDescription));
			GameTooltip_AddInstructionLine(tooltip, _L["SHORTCUT_WAYPOINT"]);
		end);
		
		-- LFG if possible
		if (WQT_WorldQuestFrame:ShouldAllowLFG(questInfo)) then
			button = rootDescription:CreateButton(OBJECTIVES_FIND_GROUP, function ()
					WQT_WorldQuestFrame:SearchGroup(questInfo);
				end, true);
		end
		
		-- Dislike toggle
		button = rootDescription:CreateCheckbox(_L["UNINTERESTED"],
							function()
								return WQT_Utils:QuestIsDisliked(questID);
							end,
							function()
								local dislike = not WQT_Utils:QuestIsDisliked(questID);
								WQT_Utils:SetQuestDisliked(questID, dislike);
							end);
		button:SetTooltip(function(tooltip, elementDescription)
			GameTooltip_SetTitle(tooltip, MenuUtil.GetElementText(elementDescription));
			GameTooltip_AddInstructionLine(tooltip, _L["SHORTCUT_DISLIKE"]);
		end);
		
		WQT_WorldQuestFrame:TriggerCallback("InitTrackDropDown", owner, rootDescription);
		
		--[[button = rootDescription:CreateButton(CANCEL, function ()
					return MenuResponse.CloseAll;
				end, true);]]
	end);
end

function WQT:IsWorldMapFiltering()
	for k, cVar in pairs(_V["WQT_CVAR_LIST"]) do
		if not C_CVar.GetCVarBool(cVar) then
			return true;
		end
	end
	return false;
end

function WQT:IsUsingFilterNr(id)
	if not WQT.settings.filters[id] then return false end
	
	local misSettings = WQT.settings.filters[id].misc;
	if (misSettings) then
		for k, flag in pairs(misSettings) do
			if (WQT.settings.general.preciseFilters and flag) then
				return true;
			elseif (not WQT.settings.general.preciseFilters and not flag) then
				return true;
			end
		end
	end
	
	local flags = WQT.settings.filters[id].flags;
	for k, flag in pairs(flags) do
		if (WQT.settings.general.preciseFilters and flag) then
			return true;
		elseif (not WQT.settings.general.preciseFilters and not flag) then
			return true;
		end
	end
	return false;
end

function WQT:IsFiltering()
	if (WQT.settings.general.emissaryOnly or WQT_WorldQuestFrame.autoEmissaryId) then return true; end
	if (not WQT.settings.general.showDisliked) then return true; end
	
	for k, category in pairs(WQT.settings.filters)do
		if (self:IsUsingFilterNr(k)) then return true; end
	end
	return false;
end

function WQT:PassesAllFilters(questInfo)
	-- Filter pass
	if(WQT_Utils:QuestIsVIQ(questInfo)) then return true; end
	
	if WQT.settings.general.emissaryOnly or WQT_WorldQuestFrame.autoEmissaryId then
		return questInfo:IsCriteria(WQT.settings.general.bountySelectedOnly or WQT_WorldQuestFrame.autoEmissaryId);
	end
	
	local filterTypes = _V["FILTER_TYPES"];

	if (not WQT.settings.general.showDisliked and questInfo:IsDisliked()) then
		return false;
	end
	
	-- For precise filters, all filters have to pass
	if (WQT.settings.general.preciseFilters)  then
		if (not  WQT:IsFiltering()) then
			return true;
		end
		local passesAll = true;
		
		if WQT:IsUsingFilterNr(filterTypes.faction) then passesAll = passesAll and WQT:PassesFactionFilter(questInfo, true) end
		if WQT:IsUsingFilterNr(filterTypes.type) then passesAll = passesAll and WQT:PassesFlagId(filterTypes.type, questInfo, true) end
		if WQT:IsUsingFilterNr(filterTypes.reward) then passesAll = passesAll and WQT:PassesFlagId(filterTypes.reward, questInfo, true) end
		
		return passesAll;
	end

	if WQT:IsUsingFilterNr(filterTypes.faction) and not WQT:PassesFactionFilter(questInfo) then return false; end
	if WQT:IsUsingFilterNr(filterTypes.type) and not WQT:PassesFlagId(filterTypes.type, questInfo) then return false; end
	if WQT:IsUsingFilterNr(filterTypes.reward) and not WQT:PassesFlagId(filterTypes.reward, questInfo) then return false; end
	
	return  true;
end

function WQT:PassesFactionFilter(questInfo, checkPrecise)
	-- Factions (1)
	local filter = WQT.settings.filters[_V["FILTER_TYPES"].faction];
	local flags = filter.flags
	local factionNone = filter.misc.none;
	local factionOther = filter.misc.other;
	local _, factionId = C_TaskQuest.GetQuestInfoByQuestID(questInfo.questID);
	local factionInfo = WQT_Utils:GetFactionDataInternal(factionId);

	-- Specific filters (matches all)
	if (checkPrecise) then
		if (factionNone and factionId) then
			return false;
		end
		if (factionOther and (not factionId or not factionInfo.unknown)) then
			return false;
		end 
		for flagKey, value in pairs(flags) do
			if (value and type(flagKey) == "number" and flagKey ~= factionId) then
				return false;
			end
		end
		return true;
	end
	
	-- General filters (matchs at least one)
	if (not factionId) then return factionNone; end
	
	if (not factionInfo.unknown) then 
		-- specific faction
		return flags[factionId];
	else
		-- other faction
		return factionOther;
	end

	return false;
end

-- Generic quest and reward type filters
function WQT:PassesFlagId(flagId ,questInfo, checkPrecise)
	local flags = WQT.settings.filters[flagId].flags
	if not flags then return false; end
	local tagInfo = questInfo:GetTagInfo();
	
	local passesPrecise = true;
	
	for flag, filterEnabled in pairs(flags) do
		if (filterEnabled) then
			local func = _V["FILTER_FUNCTIONS"][flagId] and _V["FILTER_FUNCTIONS"][flagId][flag] ;
			if(func) then 
				local passed = func(questInfo, tagInfo)
				-- If we are checking precise, combine all results. Otherwise exit out if we pass at least one
				if (WQT.settings.general.preciseFilters) then
					passesPrecise = passesPrecise and passed;
				elseif (passed) then
					return true;
				end
			end
		end
	end

	if (checkPrecise) then
		return passesPrecise;
	end
	
	return false;
end

function WQT:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("BWQDB", _V["WQT_DEFAULTS"], true);
	ConvertOldSettings(WQT.db.global.versionCheck)
	WQT_Profiles:InitSettings();
	
	-- Hightlight 'what's new'
	local currentVersion = C_AddOns.GetAddOnMetadata(addonName, "version")
	if (WQT.db.global.versionCheck < currentVersion) then
		WQT.db.global.updateSeen = false;
		WQT.db.global.versionCheck  = currentVersion;
	end
	
	_V:GeneratePatchNotes();
end

function WQT:OnEnable()
	WQT_TabNormal.Highlight:Show();
	WQT_TabNormal.TabBg:SetTexCoord(0.01562500, 0.79687500, 0.78906250, 0.95703125);
	WQT_TabWorld.TabBg:SetTexCoord(0.01562500, 0.79687500, 0.61328125, 0.78125000);
	
	-- load WorldQuestTabUtilities
	--if (WQT.settings.general.loadUtilities and C_AddOns.GetAddOnEnableState(_playerName, "WorldQuestTabUtilities") > 0 and not C_AddOns.IsAddOnLoaded("WorldQuestTabUtilities")) then
	--	LoadAddOn("WorldQuestTabUtilities");
	--end
	
	-- Place fullscreen button in saved location
	WQT_WorldMapContainerButton:LinkSettings(WQT.settings.general.fullScreenButtonPos);
	WQT_WorldMapContainer:LinkSettings(WQT.settings.general.fullScreenContainerPos);
	WQT_WorldQuestFrame:UpdateWorldMapButton();
	
	-- Apply saved filters
	if (not self.settings.general.saveFilters) then
		for k in pairs(self.settings.filters) do
			WQT:SetAllFilterTo(k, true);
		end
	end
	
	-- Sort filters
	self.filterOrders = {};
	for k, v in pairs(WQT.settings.filters) do
		self.filterOrders[k] = GetSortedFilterOrder(k);
	end
	
	-- Show default tab depending on setting
	WQT_WorldQuestFrame:SelectTab(self.settings.general.defaultTab and WQT_TabWorld or WQT_TabNormal);
	WQT_WorldQuestFrame.tabBeforeAnchor = WQT_WorldQuestFrame.selectedTab;
	
	-- Show quest log counter
	WQT_QuestLogFiller:UpdateVisibility();
	
	-- Add LFG buttons to objective tracker
	if self.settings.general.useLFGButtons then
		WQT_WorldQuestFrame.LFGButtonPool = CreateFramePool("BUTTON", nil, "WQT_LFGEyeButtonTemplate");
		hooksecurefunc(WorldQuestObjectiveTracker, "SetUpQuestBlock", function(owner, block)
				local questID = block.id;
				if (not questID) then return; end
				
				-- release button if it exists
				if (block.WQTButton) then
					WQT_WorldQuestFrame.LFGButtonPool:Release(block.WQTButton);
					block.WQTButton = nil;
				end
				
				if (not (block.groupFinderButton) and QuestUtils_IsQuestWorldQuest(questID)) then
					if (WQT_WorldQuestFrame:ShouldAllowLFG(questID)) and not block.rightEdgeFrame then
						local button = WQT_WorldQuestFrame.LFGButtonPool:Acquire();
						button.questID = questID;
						button:SetParent(block);
						button:ClearAllPoints();
						local offsetX = (block.rightButton or block.itemButton) and -13 or 6; 
						button:SetPoint("TOPRIGHT", block, offsetX, 2);
						button:Show();
						block.WQTButton = button;
					end
				end
			end);
	end
	
	-- Load settings
	WQT_SettingsFrame:Init(_V["SETTING_CATEGORIES"], _V["SETTING_LIST"]);
	
	WQT_Utils:LoadColors();
	
	-- Load externals
	self.loadableExternals = {};
	for k, external in ipairs(addon.externals) do
		if (external:IsLoaded()) then
			external:Init(WQT_Utils);
			WQT:debugPrint("External", external:GetName(), "loaded on first try.");
		elseif (external:IsLoadable()) then
			self.loadableExternals[external:GetName()] = external;
			WQT:debugPrint("External", external:GetName(), "waiting for load.");
		else
			WQT:debugPrint("External", external:GetName(), "not installed.");
		end
	end

	wipe(_V["SETTING_LIST"]);
	
	
	-- Create Filter dropdown
	WQT_InitFilterDropdown(WQT_WorldQuestFrame.FilterButton);
	
	-- Create Sort dropdown
	WQT_InitSortDropdown(WQT_WorldQuestFrame.SortDropdown);
	
	-- Create settings dropdown
	WQT_InitSettingsDropdown(WQT_WorldQuestFrame.SettingsButton);
	
	self.isEnabled = true;
end

------------------------------------------
-- 			REWARDDISPLAY MIXIN			--
------------------------------------------
-- OnLoad()
-- Reset()
-- AddRewardByInfo(rewardInfo, warmodeBonus)
-- AddReward(rewardType, texture, quality, amount, typeColor, canUpgrade, warmodeBonus)

WQT_RewardDisplayMixin = {};

function WQT_RewardDisplayMixin:OnLoad()
	self.numDisplayed = 0;
end

function WQT_RewardDisplayMixin:Reset()
	self:SetDesaturated(false);
	for k, reward in ipairs(self.rewardFrames) do
		reward:Hide();
	end
	
	self.numDisplayed = 0;
	self:SetWidth(0.1);
end

function WQT_RewardDisplayMixin:SetDesaturated(desaturate)
	self.desaturate = desaturate;
	
	self:UpdateVisuals();
end

function WQT_RewardDisplayMixin:AddRewardByInfo(rewardInfo, warmodeBonus)
	-- A bit easier when updating buttons
	self:AddReward(rewardInfo.type, rewardInfo.texture, rewardInfo.quality, rewardInfo.amount, rewardInfo.textColor, rewardInfo.canUpgrade, warmodeBonus);
end

function WQT_RewardDisplayMixin:UpdateVisuals()
	for i= 1, self.numDisplayed do
		local rewardFrame = self.rewardFrames[i];
		local r, g, b = GetItemQualityColor(rewardFrame.quality);
	
		rewardFrame:Show();
		rewardFrame.Icon:SetTexture(rewardFrame.texture);
		rewardFrame.Icon:SetDesaturated(self.desaturate);
		rewardFrame.IconBorder:SetDesaturated(self.desaturate);
		if (self.desaturate) then
			rewardFrame.IconBorder:SetVertexColor(1, 1, 1);
		else
			rewardFrame.IconBorder:SetVertexColor(r, g, b);
		end

		-- Conduits have special borders
		rewardFrame.ConduitCorners:Hide();
		if (rewardFrame.rewardType == WQT_REWARDTYPE.conduit) then
			rewardFrame.IconBorder:SetAtlas("conduiticonframe");
			rewardFrame.ConduitCorners:Show();
		elseif (rewardFrame.rewardType == WQT_REWARDTYPE.relic) then
			rewardFrame.IconBorder:SetTexture("Interface/Artifacts/RelicIconFrame");
		else
			rewardFrame.IconBorder:SetTexture("Interface/Common/WhiteIconFrame");
		end
		if (self.desaturate) then
			rewardFrame.ConduitCorners:SetDesaturated(self.desaturate);
		end
	
		local amount = rewardFrame.amount;
		rewardFrame.Amount:Hide();
		if (amount > 1) then
			rewardFrame.Amount:Show();
			
			if (rewardFrame.rewardType == WQT_REWARDTYPE.gold) then
				amount = floor(amount / 10000);
			end
			
			local amountDisplay = GetLocalizedAbbreviatedNumber(amount);
			
			if (rewardFrame.rewardType == WQT_REWARDTYPE.relic) then
				amountDisplay = "+"..amountDisplay;
			elseif (rewardFrame.canUpgrade) then
				amountDisplay = amountDisplay.."+";
			end
			rewardFrame.Amount:SetText(amountDisplay);
	
			-- Color reward amount for certain types
			r, g, b = 1, 1, 1
			if (not self.desaturate and WQT.settings.list.amountColors) then
				r, g, b = rewardFrame.typeColor:GetRGB();
			end
	
			rewardFrame.Amount:SetVertexColor(r, g, b);
		end
	end
end

function WQT_RewardDisplayMixin:AddReward(rewardType, texture, quality, amount, typeColor, canUpgrade, warmodeBonus)
	local displayTypeSetting = WQT.settings.list.rewardDisplay;

	-- Limit the amount of rewards shown
	if (self.numDisplayed >= WQT.settings.list.rewardNumDisplay) then return; end
	
	self.numDisplayed = self.numDisplayed + 1;
	local num = self.numDisplayed;
	
	amount = amount or 1;
	-- Calculate warmode bonus
	if (warmodeBonus) then
		amount = WQT_Utils:CalculateWarmodeAmount(rewardType, amount);
	end
	
	self:SetWidth(num * 29 - 1);
	local rewardFrame = self.rewardFrames[num];
	rewardFrame.rewardType = rewardType;
	rewardFrame.texture = texture;
	rewardFrame.quality = quality;
	rewardFrame.amount = amount;
	rewardFrame.typeColor = typeColor;
	rewardFrame.canUpgrade = canUpgrade;
	
	self:UpdateVisuals();
end

------------------------------------------
-- 			LISTBUTTON MIXIN			--
------------------------------------------
--
-- OnClick(button)
-- SetEnabledMixin(value)	Custom version of 'disable' for the sake of combat
-- OnUpdate()
-- OnLeave()
-- OnEnter()
-- UpdateQuestType(questInfo)
-- Update(questInfo, shouldShowZone)
-- FactionOnEnter(frame)

WQT_ListButtonMixin = {}

function WQT_ListButtonMixin:OnLoad()
	self.TrackedBorder:SetFrameLevel(self:GetFrameLevel() + 2);
	self.Highlight:SetFrameLevel(self:GetFrameLevel() + 2);
	self:EnableKeyboard(false);
	self.UpdateTooltip = function() self:OnEnter() end;
	self.timer = 0;
end

function WQT_ListButtonMixin:OnClick(button)
	WQT_Utils:HandleQuestClick(self, self.questInfo, button);
end

-- Custom enable/disable
function WQT_ListButtonMixin:SetEnabledMixin(value)
	value = value==nil and true or value;
	self:SetEnabled(value);
	self:EnableMouse(value);
	self.Faction:EnableMouse(value);
end

function WQT_ListButtonMixin:OnUpdate(elapsed)
	self.timer = self.timer + elapsed;
	
	if (self.timer >= 1) then 
		self:UpdateTime();
		self.timer = 0;
	end;
end

function WQT_ListButtonMixin:UpdateTime()
	if ( not self.questInfo or not self:IsShown() or self.questInfo.seconds == 0) then return; end
	local _, timeString, color, _, _, category = WQT_Utils:GetQuestTimeString(self.questInfo, WQT.settings.list.fullTime);

	if (self.questInfo:IsDisliked() or (not WQT.settings.list.colorTime and category ~= _V["TIME_REMAINING_CATEGORY"].critical)) then
		color = _V["WQT_WHITE_FONT_COLOR"];
	end
	self.Time:SetTextColor(color.r, color.g, color.b, 1);
	self.Time:SetText(timeString);
end

function WQT_ListButtonMixin:OnLeave()
	self.Highlight:Hide();
	WQT_WorldQuestFrame.pinDataProvider:SetQuestIDPinged(self.questInfo.questID, false);
	WQT_WorldQuestFrame:HideWorldmapHighlight();
	GameTooltip:Hide();
	GameTooltip.ItemTooltip:Hide();
	
	local isDisliked = self.questInfo:IsDisliked();
	self:SetAlpha(isDisliked and 0.75 or 1);
	
	WQT:HideDebugTooltip()
end

function WQT_ListButtonMixin:OnEnter()
	local questInfo = self.questInfo;
	if (not questInfo) then return; end
	self.Highlight:Show();
	
	WQT_WorldQuestFrame.pinDataProvider:SetQuestIDPinged(self.questInfo.questID, true);
	WQT_WorldQuestFrame:ShowWorldmapHighlight(questInfo.questID);
	
	local style = nil;
	if (questInfo:IsQuestOfType(WQT_QUESTTYPE.calling)) then
		if (C_QuestLog.IsOnQuest(questInfo.questID)) then
			style = _V["TOOLTIP_STYLES"].callingActive;
		else
			style = _V["TOOLTIP_STYLES"].callingAvailable;
		end
	end

	WQT_Utils:ShowQuestTooltip(self, questInfo, style);
	self:SetAlpha(1);
end

function WQT_ListButtonMixin:UpdateQuestType(questInfo)

	local typeFrame = self.Type;
	local isCriteria = questInfo:IsCriteria(WQT.settings.general.bountySelectedOnly);
	local tagInfo = questInfo:GetTagInfo();
	local isElite = tagInfo and tagInfo.isElite;
	
	typeFrame:Show();
	typeFrame:SetWidth(typeFrame:GetHeight());
	typeFrame.Texture:Show();
	typeFrame.Elite:SetShown(isElite);

	if (not tagInfo or not tagInfo.quality or tagInfo.quality == Enum.WorldQuestQuality.Common) then
		typeFrame.Bg:SetTexture("Interface/WorldMap/UI-QuestPoi-NumberIcons");
		typeFrame.Bg:SetTexCoord(0.875, 1, 0.375, 0.5);
		typeFrame.Bg:SetSize(28, 28);
	elseif (tagInfo.quality == Enum.WorldQuestQuality.Rare) then
		typeFrame.Bg:SetAtlas("worldquest-questmarker-rare");
		typeFrame.Bg:SetTexCoord(0, 1, 0, 1);
		typeFrame.Bg:SetSize(18, 18);
	elseif (tagInfo.quality == Enum.WorldQuestQuality.Epic) then
		typeFrame.Bg:SetAtlas("worldquest-questmarker-epic");
		typeFrame.Bg:SetTexCoord(0, 1, 0, 1);
		typeFrame.Bg:SetSize(18, 18);
	end
	
	-- Update Icon
	local atlasTexture, sizeX, sizeY, hideBG = WQT_Utils:GetCachedTypeIconData(questInfo);

	typeFrame.Texture:SetAtlas(atlasTexture);
	typeFrame.Texture:SetSize(sizeX, sizeY);
	typeFrame.Bg:SetAlpha(hideBG and 0 or 1);
	typeFrame.CriteriaGlow:SetShown(isCriteria);
	
	if (isCriteria) then
		if (isElite) then
			typeFrame.CriteriaGlow:SetAtlas("worldquest-questmarker-dragon-glow", false);
			typeFrame.CriteriaGlow:SetPoint("CENTER", 0, -1);
		else
			typeFrame.CriteriaGlow:SetAtlas("worldquest-questmarker-glow", false);
			typeFrame.CriteriaGlow:SetPoint("CENTER", 0, 0);
		end
	end
end

function WQT_ListButtonMixin:Update(questInfo, shouldShowZone)
	if (self.questInfo ~= questInfo) then
		self.TrackedBorder:Hide();
		self.Highlight:Hide();
		self:Hide();
	end
	
	if not questInfo then
		return;
	end
	
	-- Force update rewards of quests
	--questInfo:LoadRewards(true);
	
	self:Show();
	self.questInfo = questInfo;
	self.zoneId = C_TaskQuest.GetQuestZoneID(questInfo.questID);
	self.questID = questInfo.questID;
	local isDisliked = questInfo:IsDisliked();
	self:SetAlpha(isDisliked and 0.75 or 1);
	
	-- Title
	local title, factionId = C_TaskQuest.GetQuestInfoByQuestID(questInfo.questID);

	if (not questInfo.isValid) then
		title = "|cFFFF0000(Invalid) " .. title;
	elseif (not questInfo.passedFilter) then
		title = "|cFF999999(Filtered) " .. title;
	elseif (isDisliked) then
		title = "|cFF999999" .. title;
	end
	
	self.Title:SetText(title);
	self.Title:ClearAllPoints()
	self.Title:SetPoint("RIGHT", self.Rewards, "LEFT", -5, 0);
	
	if (WQT.settings.list.factionIcon) then
		self.Title:SetPoint("BOTTOMLEFT", self.Faction, "RIGHT", 5, 1);
	elseif (WQT.settings.list.typeIcon) then
		self.Title:SetPoint("BOTTOMLEFT", self.Type, "RIGHT", 5, 1);
	else
		self.Title:SetPoint("BOTTOMLEFT", self, "LEFT", 10, 0);
	end

	-- Time and zone
	local extraSpace = WQT.settings.list.factionIcon and 0 or 14;
	extraSpace = extraSpace + (WQT.settings.list.typeIcon and 0 or 14);
	local timeWidth = extraSpace + (WQT.settings.list.fullTime and 70 or 60);
	local zoneWidth = extraSpace + (WQT.settings.list.fullTime and 80 or 90);
	if (not shouldShowZone) then
		timeWidth = timeWidth + zoneWidth;
		zoneWidth = 0.1;
	end
	self.Time:SetWidth(timeWidth)
	self.Extra:SetWidth(zoneWidth)
	
	self:UpdateTime();
	
	local zoneName = "";
	if (shouldShowZone) then
		local mapInfo = WQT_Utils:GetMapInfoForQuest(questInfo.questID);
		if (mapInfo) then
			zoneName = mapInfo.name;
		end
	end
	
	self.Extra:SetText(zoneName);
	
	-- Highlight
	local showHighLight = self:IsMouseOver() or self.Faction:IsMouseOver() or (WQT_QuestScrollFrame.PoIHoverId and WQT_QuestScrollFrame.PoIHoverId == questInfo.questID)
	self.Highlight:SetShown(showHighLight);
			
	-- Faction icon
	if (WQT.settings.list.factionIcon) then
		self.Faction:Show();
		local factionData = WQT_Utils:GetFactionDataInternal(factionId);

		self.Faction.Icon:SetTexture(factionData.texture);
		self.Faction:SetWidth(self.Faction:GetHeight());
	else
		self.Faction:Hide();
		self.Faction:SetWidth(0.1);
	end
	self.Faction.Icon:SetDesaturated(isDisliked);
	
	-- Type icon
	if (WQT.settings.list.typeIcon) then
		self:UpdateQuestType(questInfo)
	else
		self.Type:Hide()
		self.Type:SetWidth(0.1);
	end
	self.Type.Bg:SetDesaturated(isDisliked);
	self.Type.Texture:SetDesaturated(isDisliked);
	self.Type.Elite:SetDesaturated(isDisliked);

	-- Warband bonus
	if (WQT.settings.list.showWarbandBonus) and questInfo:HasWarbandBonus() then
		self.WarbandBonus:Show();
	else
		self.WarbandBonus:Hide();
	end

	-- Rewards
	self.Rewards:Reset();
	self.Rewards:SetDesaturated(isDisliked);
	for k, rewardInfo in questInfo:IterateRewards() do
		self.Rewards:AddRewardByInfo(rewardInfo, C_QuestLog.QuestCanHaveWarModeBonus(self.questID));
	end

	-- Show border if quest is tracked
	local isHardWatched = WQT_Utils:QuestIsWatchedManual(questInfo.questID);
	if (isHardWatched) then
		self.TrackedBorder:Show();
	else
		self.TrackedBorder:Hide();
	end
	
	WQT_WorldQuestFrame:TriggerCallback("ListButtonUpdate", self)
end

function WQT_ListButtonMixin:FactionOnEnter(frame)
	self.Highlight:Show();
	local _, factionId = C_TaskQuest.GetQuestInfoByQuestID(self.questInfo.questID);
	if (factionId) then
		local factionInfo = WQT_Utils:GetFactionDataInternal(factionId)
		GameTooltip:SetOwner(frame, "ANCHOR_RIGHT", -5, -10);
		GameTooltip:SetText(factionInfo.name, nil, true);
	end
	
end

------------------------------------------
-- 			SCROLLLIST MIXIN			--
------------------------------------------
--
-- OnLoad()
-- SetButtonsEnabled(value)
-- ApplySort()
-- UpdateFilterDisplay()
-- UpdateQuestList()
-- DisplayQuestList(skipPins)
-- ScrollFrameSetEnabled(enabled)

WQT_ScrollListMixin = {};

function WQT_ScrollListMixin:OnLoad()
	-- Call default scrollframe onload manually??
	ScrollFrame_OnLoad(self);
	
	self.questList = {};
	self.questListDisplay = {};
	
	self:RegisterCallback("OnVerticalScroll", function(offset)
		self:UpdateBottomShadow(offset);
	end);

	self:RegisterCallback("OnScrollRangeChanged", function(offset)
		self:UpdateBottomShadow(offset);
	end);
	
	self.worldquestsFramePool = CreateFramePool("BUTTON", WQT_QuestScrollFrame.Contents, "WQT_QuestTemplate");
end

function WQT_ScrollListMixin:UpdateBottomShadow(offset)
	local shadow = self.BorderFrame.Shadow;
	local height = shadow:GetHeight();
	local delta = self:GetVerticalScrollRange() - self:GetVerticalScroll();
	local alpha = Clamp(delta/height, 0, 1);
	shadow:SetAlpha(alpha);
end

function WQT_ScrollListMixin:ResetButtons()
	local buttons = self.buttons;
	if buttons == nil then return; end
	for i=1, #buttons do
		local button = buttons[i];
		button.TrackedBorder:Hide();
		button.Highlight:Hide();
		button:Hide();
		button.questInfo = nil;
	end
end

function WQT_ScrollListMixin:SetButtonsEnabled(value)
	value = value==nil and true or value;
	local buttons = self.buttons;
	if not buttons then return end;
	
	for k, button in ipairs(buttons) do
		button:SetEnabledMixin(value);
		button:EnableMouse(value);
		button:EnableMouseWheel(value);
	end
end

function WQT_ScrollListMixin:ApplySort()
	local list = self.questListDisplay;
	local sortOption =  WQT.settings.general.sortBy;
	table.sort(list, function (a, b) return SortQuestList(a, b, sortOption); end);
end

function WQT_ScrollListMixin:UpdateFilterDisplay()
	local isFiltering = WQT:IsFiltering();
	
	-- There are world quests available so hide these texts
	WQT_WorldQuestFrame.ScrollFrame.EmptyText:SetShown(false);
	WQT_WorldQuestFrame.ScrollFrame.NoFilterResultsText:SetShown(false);
end

function WQT_ScrollListMixin:FilterQuestList()
	wipe(self.questListDisplay);
	local WQTFiltering = WQT:IsFiltering();
	local BlizFiltering = WQT:IsWorldMapFiltering();
	
	for k, questInfo in ipairs(self.questList) do
		questInfo.passedFilter = false;
		if questInfo.isValid and not questInfo.alwaysHide and questInfo.hasRewardData and not questInfo:IsExpired() then
			local passed = false;
			-- Filter passes don't care about anything else
			if(WQT_Utils:QuestIsVIQ(questInfo)) then
				passed = true;
			else
				-- Official filtering
				if (questInfo.questID < 70000) or QuestUtils_IsQuestWorldQuest(questInfo.questID) or QuestUtils_IsQuestBonusObjective(questInfo.questID) then
					passed = BlizFiltering and WorldMap_DoesWorldQuestInfoPassFilters(questInfo) or not BlizFiltering;
					-- Add-on filters
					if (passed and WQTFiltering) then
						passed = WQT:PassesAllFilters(questInfo);
					end
				end
			end
			
			questInfo.passedFilter = passed;
			
			if (questInfo.passedFilter) then
				table.insert(self.questListDisplay, questInfo);
			end
		end
		
		-- In debug, still filter, but show everything.
		if (not questInfo.passedFilter and addon.debug) then
			table.insert(self.questListDisplay, questInfo);
		end
	end
	
	WQT_WorldQuestFrame:TriggerCallback("FilterQuestList");
end

function WQT_ScrollListMixin:UpdateQuestList()
	local flightShown = (FlightMapFrame and FlightMapFrame:IsShown() or TaxiRouteMap:IsShown() );
	local worldShown = WorldMapFrame:IsShown();
	
	if (not (flightShown or worldShown)) then return end	
	
	self.questList = WQT_WorldQuestFrame.dataProvider:GetIterativeList();
	-- Update reward priorities
	for k, questInfo in ipairs(self.questList) do
		questInfo:ParseRewards();
	end
	
	self:FilterQuestList();
	self:ApplySort();
	self:DisplayQuestList();
	WQT_WorldQuestFrame:TriggerCallback("UpdateQuestList");
end

function WQT_ScrollListMixin:SetFrameLayoutIndex(frame)
	frame.layoutIndex = self.layoutIndex or 1;
	self.layoutIndex = frame.layoutIndex + 1;
end

function WQT_ScrollListMixin:ResetLayoutIndex()
	self.layoutIndex = 1;
end

function WQT_ScrollListMixin:DisplayQuestList()	
	WQT_QuestScrollFrame.worldquestsFramePool:ReleaseAll();
	self:ResetLayoutIndex();
	
	local mapId = WorldMapFrame.mapID;
	if (((FlightMapFrame and FlightMapFrame:IsShown()) or TaxiRouteMap:IsShown()) and not _WFMLoaded) then 
		local taxiId = FlightMapFrame and FlightMapFrame:GetMapID() or GetTaxiMapID()
		mapId = (taxiId and taxiId > 0) and taxiId or mapId;
	end
	local mapInfo = WQT_Utils:GetCachedMapInfo(mapId or 0);
	local list = self.questListDisplay;
	local totalQuests = #self.questList;
	self.numDisplayed = #list;
	
	if #list == 0 then
		-- 0 world quests??? Are we filtering? If yes then show no results available text; otherwise, show empty text (no world quest)
		if WQT:IsFiltering() then
			WQT_WorldQuestFrame.ScrollFrame.NoFilterResultsText:SetShown(true);
		else
			WQT_WorldQuestFrame.ScrollFrame.EmptyText:SetShown(true);
		end
		self:UpdateBackground();
		return;
	end
	
	local currentScroll = WQT_QuestScrollFrame.ScrollBar:GetScrollPercentage();
	-- Now start from zero
	WQT_QuestScrollFrame.ScrollBar:ScrollToBegin();
	
	local shouldShowZone = WQT.settings.list.showZone and (WQT.settings.list.alwaysAllQuests or (mapInfo and (mapInfo.mapType == Enum.UIMapType.Continent or mapInfo.mapType == Enum.UIMapType.World))); 

	self:UpdateFilterDisplay();
	
	-- Update list buttons
	self.scrollLocked = WQT_WorldQuestFrame.dataProvider:IsUpdating();
		
	for i=1, #self.questList do
		local button = WQT_QuestScrollFrame.worldquestsFramePool:Acquire();
		local offset = WQT_QuestScrollFrame:GetVerticalScroll();
		local displayIndex = i + offset;
		
		self:SetFrameLayoutIndex(button);
		
		if not self.scrollLocked then
			button:Update(list[displayIndex], shouldShowZone);
		end
	end
	
	-- Update scroll to current value
	if currentScroll > 0 then
		WQT_QuestScrollFrame.ScrollBar:SetScrollPercentage(currentScroll, true);
	end
	
	if (not self.scrollLocked) then
		WQT_QuestScrollFrame.Contents:Layout();
	end
	
	-- Update background
	self:UpdateBackground();
	
	WQT_WorldQuestFrame:TriggerCallback("DisplayQuestList");
end

function WQT_ScrollListMixin:UpdateBackground()
	if (C_AddOns.IsAddOnLoaded("Aurora") or (WorldMapFrame:IsShown() and WQT_WorldMapContainer:IsShown())) then
		WQT_QuestScrollFrame.Background:SetAlpha(0);
	else
		WQT_QuestScrollFrame.Background:SetAlpha(1);
		-- Don't change the backgound if data is buffering to prevent the background flashing
		if (not WQT_WorldQuestFrame.dataProvider:IsBuffereingQuests()) then
			if self.numDisplayed == 0 and not WQT:IsFiltering() then
				WQT_QuestScrollFrame.Background:SetAtlas("QuestLog-empty-quest-background", true);
			else
				WQT_QuestScrollFrame.Background:SetAtlas("QuestLog-main-background", true);
			end
		end
	end
end

function WQT_ScrollListMixin:ScrollFrameSetEnabled(enabled)
	self:EnableMouse(enabled)
	self:EnableMouse(enabled);
	self:EnableMouseWheel(enabled);
	local buttons = self.buttons;
	for k, button in ipairs(buttons) do
		button:EnableMouse(enabled);
	end
end

------------------------------------------
-- 			QUESTCOUNTER MIXIN			--
------------------------------------------
--
-- OnLoad()
-- InfoOnEnter(frame)
-- UpdateText()

WQT_QuestCounterMixin = {}

function WQT_QuestCounterMixin:OnLoad()
	self:SetFrameLevel(self:GetParent():GetFrameLevel() +5);
	self.falseCounted = {};
	self.numQuests = 0
end

-- Entering the hidden quests indicator
function WQT_QuestCounterMixin:InfoOnEnter(frame)
	GameTooltip:SetOwner(frame, "ANCHOR_RIGHT");
	GameTooltip:SetText(_L["QUEST_COUNTER_TITLE"], 1, 1, 1, 1, true);
	GameTooltip:AddLine(_L["QUEST_COUNTER_INFO"]:format(#self.falseCounted), nil, nil, nil, true);
	
	local _, questCount = C_QuestLog.GetNumQuestLogEntries();
	GameTooltip:AddDoubleLine("API - Addon = Displayed", ("|cFFFFFFFF%d - %d = %d|r"):format(questCount , #self.falseCounted, self.numQuests), 1, 1, 1, 1, 1, 1, true);
	--GameTooltip:AddLine(, nil, nil, nil, true);
	
	-- Add culprits
	for k, i in ipairs(self.falseCounted) do
		local info = C_QuestLog.GetInfo(i);
		local tagInfo = C_QuestLog.GetQuestTagInfo(info.questID);
		GameTooltip:AddDoubleLine(string.format("%s (%s)", info.title, info.questID), tagInfo and tagInfo.tagName or "No tag", 1, 1, 1, 1, 1, 1, true);
	end
	
	GameTooltip:Show();
end

function WQT_QuestCounterMixin:UpdateText()
	local numQuests, maxQuests, color = WQT_Utils:GetQuestLogInfo(self.falseCounted);
	self.QuestCount:SetText(GENERIC_FRACTION_STRING_WITH_SPACING:format(numQuests, maxQuests));
	self.QuestCount:SetTextColor(color.r, color.g, color.b);
	
	self.numQuests = numQuests;
end

function WQT_QuestCounterMixin:UpdateVisibility()
	local shouldShow = WQT.settings.general.questCounter and QuestScrollFrame:IsShown();
	-- Comment temporally, need reposition
	--self:SetShown(shouldShow);
end

------------------------------------------
-- 		CONSTRAINED CHILD MIXIN		--
------------------------------------------
-- 
-- OnLoad()
-- OnDragStart()	
-- OnDragStop()
-- OnUpdate()
-- SetStartPosition(anchor, x, y)
-- ConstrainPosition()
--

WQT_ConstrainedChildMixin = {}

function WQT_ConstrainedChildMixin:OnLoad(anchor)
	self.margins = {["left"] = 0, ["right"] = 0, ["top"] = 0, ["bottom"] = 0};
	self.anchor = "BOTTOMLEFT";
	self.left = 0;
	self.bottom = 0;
	self.dragMouseOffset = {["x"] = 0, ["y"] = 0};
	self.firstSetup = true;
end

function WQT_ConstrainedChildMixin:OnDragStart()
	if not self:IsMovable() then
		return;
	end
	
	self:StartMoving();
	local scale = self:GetEffectiveScale();
	local fx = self:GetLeft();
	local  fy = self:GetBottom();
	local x, y = GetCursorPosition();
	x = x / scale;
	y = y / scale;
	
	self.dragMouseOffset.x = x - fx;
	self.dragMouseOffset.y = y - fy;
	self.isBeingDragged = true;
end

function WQT_ConstrainedChildMixin:OnDragStop()
	if(self.isBeingDragged) then
		self.isBeingDragged = false;
		self:StopMovingOrSizing()
		self:ConstrainPosition();
		
		if (self.settings) then
			self.settings.anchor = self.anchor;
			self.settings.x = self.left;
			self.settings.y = self.bottom;
		end
	end
end

function WQT_ConstrainedChildMixin:OnUpdate()
	--
	if (self.isBeingDragged) then
		self:ConstrainPosition();
	end
end

function WQT_ConstrainedChildMixin:LinkSettings(settings)
	self:ClearAllPoints();
	self:SetPoint(settings.anchor, self:GetParent(), settings.anchor, settings.x, settings.y);
	self.settings = settings;
end

-- Constrain the frame to stay inside the borders of the parent frame
function WQT_ConstrainedChildMixin:ConstrainPosition()
	
	local parent = self:GetParent();
	local l1, b1, w1, h1 = self:GetRect();
	local l2, b2, w2, h2 = parent:GetRect();

	-- If we're being dragged, we should make calculations based on the mouse position instead
	-- Start dragging at middle of frame -> Mouse goes outside bounds -> Doesn't move until mouse is back at the middle
	-- Oterwise the frame starts moving when the mouse is no longer near it.
	if (self.isBeingDragged) then
		local scale = self:GetEffectiveScale();
		l1, b1 =  GetCursorPosition();
		l1 = l1 / scale;
		b1 = b1 / scale;
		l1 = l1 - self.dragMouseOffset.x;
		b1 = b1 - self.dragMouseOffset.y;
	end
	
	local left = (l1-l2);
	local bottom = (b1-b2);
	local right = (l2+w2) - (l1+w1) - self.margins.right;
	local top = (b2+h2) - (b1+h1) - self.margins.top;
	-- Check if any side passes a edge (including margins)
	local SetConstrainedPos = false;
	if (left < self.margins.left) then 
		left = self.margins.left;
		SetConstrainedPos = true;
	end
	if (bottom < self.margins.bottom) then 
		bottom = self.margins.bottom;
		SetConstrainedPos = true;
	end
	if (right < 0) then 
		left = (w2-w1 - self.margins.right);
		SetConstrainedPos = true;
	end
	if (top < 0) then 
		bottom = (h2-h1 - self.margins.top);
		SetConstrainedPos = true;
	end
	
	-- Find best fitting anchor
	local anchorH = "LEFT";
	local anchorV = "BOTTOM";
	if (left + w1/2 >= w2/2) then
		anchorH = "RIGHT";
		left = left - w2 + w1;
	end
	if (bottom + h1/2 >= h2/2) then
		anchorV = "TOP";
		bottom = bottom - h2 + h1;
	end
	
	local anchor = anchorV .. anchorH;
	
	self.anchor = anchor;
	self.left = left;
	self.bottom = bottom;

	-- If the frame had to be constrained, force the constrained position
	if (SetConstrainedPos) then
		self:ClearAllPoints();
		self:SetPoint(self.anchor, parent, self.anchor, left, bottom);
	end
end

------------------------------------------
-- 				CORE MIXIN				--
------------------------------------------
-- 
-- ShowWorldmapHighlight(questID)
-- HideWorldmapHighlight()
-- TriggerEvent(event, ...)
-- RegisterCallback(func)
-- OnLoad()
-- UpdateBountyCounters()
-- RepositionBountyTabs()
-- AddBountyCountersToTab(tab)
-- UpdateWorldMapButton()
-- ShowHighlightOnMapFilters()
-- FilterClearButtonOnClick()
-- SearchGroup(questInfo)
-- ShouldAllowLFG(questInfo)
-- SetCvarValue(flagKey, value)
-- SetCustomEnabled(value)
-- SelectTab(tab)		1. Default questlog  2. WQT  3. Quest details
-- ChangeAnchorLocation(anchor)		Show list on a different container using _V["LIST_ANCHOR_TYPE"] variable
-- :<event> -> ADDON_LOADED, PLAYER_REGEN_DISABLED, PLAYER_REGEN_ENABLED, QUEST_TURNED_IN, PVP_TIMER_UPDATE, WORLD_QUEST_COMPLETED_BY_SPELL, QUEST_LOG_UPDATE, QUEST_WATCH_LIST_CHANGED

WQT_CoreMixin = CreateFromMixins(WQT_CallbackMixin, WQT_EventHookMixin);

function WQT_CoreMixin:TryHideOfficialMapPin(pin)
	if (WQT.settings.pin.disablePoI) then return; end
	
	local questInfo = self.dataProvider:GetQuestById(pin.questID)
	if (questInfo and questInfo.isValid) then
		pin:Hide();
	end
end

function WQT_CoreMixin:HideOfficialMapPins()
	if (WQT.settings.pin.disablePoI) then return; end
	
	if (WorldMapFrame:IsShown()) then
		local mapWQProvider = WQT_Utils:GetMapWQProvider();
		for _, pin in pairs(mapWQProvider.activePins) do
			self:TryHideOfficialMapPin(pin);
		end
		
		-- Bonus world quests
		WQT_Utils:ItterateAllBonusObjectivePins(function(pin) self:TryHideOfficialMapPin(pin); end);
	end
end

-- Mimics hovering over a zone or continent, based on the zone the map is in
function WQT_CoreMixin:ShowWorldmapHighlight(questID)
	local zoneId = C_TaskQuest.GetQuestZoneID(questID);
	local areaId = WorldMapFrame.mapID;
	local coords = _V["WQT_ZONE_MAPCOORDS"][areaId] and _V["WQT_ZONE_MAPCOORDS"][areaId][zoneId];
	local mapInfo = WQT_Utils:GetCachedMapInfo(zoneId);
	-- We can't use parentMapID for cases like Cape of Stranglethorn
	local continentID = WQT_Utils:GetContinentForMap(zoneId);
	-- Highlihght continents on world view
	-- 947 == Azeroth world map
	if (not coords and areaId == 947 and continentID) then
		coords = _V["WQT_ZONE_MAPCOORDS"][947][continentID];
		mapInfo = WQT_Utils:GetCachedMapInfo(continentID);
	end
	
	if (not coords or not mapInfo) then return; end;

	WorldMapFrame.ScrollContainer:GetMap():TriggerEvent("SetAreaLabel", MAP_AREA_LABEL_TYPE.POI, mapInfo.name);

	-- Now we cheat by acting like we moved our mouse over the relevant zone
	WQT_MapZoneHightlight:SetParent(WorldMapFrame.ScrollContainer.Child);
	WQT_MapZoneHightlight:SetFrameLevel(5);
	local fileDataID, atlasID, texPercentageX, texPercentageY, textureX, textureY, scrollChildX, scrollChildY = C_Map.GetMapHighlightInfoAtPosition(WorldMapFrame.mapID, coords.x, coords.y);
	if (fileDataID and fileDataID > 0) or (atlasID) then
		WQT_MapZoneHightlight.Texture:SetTexCoord(0, texPercentageX, 0, texPercentageY);
		local width = WorldMapFrame.ScrollContainer.Child:GetWidth();
		local height = WorldMapFrame.ScrollContainer.Child:GetHeight();
		WQT_MapZoneHightlight.Texture:ClearAllPoints();
		if (atlasID) then
			WQT_MapZoneHightlight.Texture:SetAtlas(atlasID, true, "TRILINEAR");
			scrollChildX = ((scrollChildX + 0.5*textureX) - 0.5) * width;
			scrollChildY = -((scrollChildY + 0.5*textureY) - 0.5) * height;
			WQT_MapZoneHightlight.Texture:SetPoint("CENTER", scrollChildX, scrollChildY);
			WQT_MapZoneHightlight:Show();
		else
			WQT_MapZoneHightlight.Texture:SetTexture(fileDataID, nil, nil, "LINEAR");
			textureX = textureX * width;
			textureY = textureY * height;
			scrollChildX = scrollChildX * width;
			scrollChildY = -scrollChildY * height;
			if textureX > 0 and textureY > 0 then
				WQT_MapZoneHightlight.Texture:SetWidth(textureX);
				WQT_MapZoneHightlight.Texture:SetHeight(textureY);
				WQT_MapZoneHightlight.Texture:SetPoint("TOPLEFT", WQT_MapZoneHightlight:GetParent(), "TOPLEFT", scrollChildX, scrollChildY);
				WQT_MapZoneHightlight:Show();
			end
		end
	end
	
	self.resetLabel = true;
end

function WQT_CoreMixin:HideWorldmapHighlight()
	WQT_MapZoneHightlight:Hide();
	if (self.resetLabel) then
		WorldMapFrame.ScrollContainer:GetMap():TriggerEvent("ClearAreaLabel", MAP_AREA_LABEL_TYPE.POI);
		self.resetLabel = false;
	end
end

function WQT_CoreMixin:OnLoad()
	self.WQT_Utils = WQT_Utils;
	self.variables = addon.variables;

	-- Add utilities options to the settings if it's installed but not enabled
	--[[if (_utilitiesInstalled) then
		for k, setting in ipairs(_V["SETTING_UTILITIES_LIST"]) do
			tinsert(_V["SETTING_LIST"], setting);
		end
	end]]

	-- Quest Dataprovider
	self.dataProvider = CreateAndInitFromMixin(WQT_DataProvider);

	-- Pin Dataprovider
	self.pinDataProvider = CreateAndInitFromMixin(WQT_PinDataProvider);
	self.bountyCounterPool = CreateFramePool("FRAME", self, "WQT_BountyCounterTemplate");
	
	self:SetFrameLevel(self:GetParent():GetFrameLevel()+4);
	self.Blocker:SetFrameLevel(self:GetFrameLevel()+4);
	
	self.dataProvider:RegisterCallback("WaitingRoom", function() 
			--if (InCombatLockdown()) then return end;
			WQT_QuestScrollFrame:ApplySort();
			WQT_QuestScrollFrame:FilterQuestList();
			WQT_QuestScrollFrame:UpdateQuestList();
			WQT_WorldQuestFrame:TriggerCallback("WaitingRoomUpdated")
		end, addonName)
		
	self.dataProvider:RegisterCallback("QuestsLoaded", function() 
			self.ScrollFrame:UpdateQuestList(); 
			-- Update the quest number counter
			WQT_QuestLogFiller:UpdateText();
			WQT_WorldQuestFrame:TriggerCallback("QuestsLoaded")
		end, addonName)
	
	self.dataProvider:RegisterCallback("BufferUpdated", function(progress) 
			if (progress == 0 or progress == 1) then
				self.ProgressBar:Hide();
			else
				CooldownFrame_SetDisplayAsPercentage(self.ProgressBar, progress);
				self.ProgressBar.Pointer:SetRotation(-progress*6.2831);
			end
		end, addonName)

	-- Events
	self:RegisterEvent("PLAYER_REGEN_DISABLED");
	self:RegisterEvent("PLAYER_REGEN_ENABLED");
	self:RegisterEvent("QUEST_TURNED_IN");
	self:RegisterEvent("WORLD_QUEST_COMPLETED_BY_SPELL"); -- Class hall items
	self:RegisterEvent("PVP_TIMER_UPDATE"); -- Warmode toggle because WAR_MODE_STATUS_UPDATE doesn't seems to fire when toggling warmode
	self:RegisterEvent("ADDON_LOADED");
	self:RegisterEvent("QUEST_WATCH_LIST_CHANGED");
	self:RegisterEvent("TAXIMAP_OPENED");
	self:RegisterEvent("PLAYER_LOGOUT");
	
	self:SetScript("OnEvent", function(self, event, ...) 
			if (self[event]) then 
				self[event](self, ...) 
			else 
				WQT:debugPrint("WQT missing function for:",event); 
			end 
			
			WQT_EventHookMixin.OnEvent(self, event, ...);
		end)

	-- Slashcommands
	SLASH_WQTSLASH1 = '/wqt';
	SLASH_WQTSLASH2 = '/worldquesttab';
	SlashCmdList["WQTSLASH"] = slashcmd
	
	

	--
	-- Function hooks
	-- 
	
	-- Show quest tab when leaving quest details
	hooksecurefunc("QuestMapFrame_ReturnFromQuestDetails", function()
			self:SelectTab(WQT_TabNormal);
		end)
	-- When untracking a quest with details open
	hooksecurefunc("QuestMapFrame_CloseQuestDetails", function()
			if (self.selectedTab == WQT_TabDetails) then
				self:SelectTab(WQT_TabNormal);
			end
		end)
		
	
	-- World map
	-- If we were reading details when we switch maps, change back to normal quests
	EventRegistry:RegisterCallback("MapCanvas.MapSet", function() 
			-- Now we do it modern way.
			if (self.selectedTab == WQT_TabDetails) then
				self:SelectTab(WQT_TabNormal); 
			end
		end);
	
	-- Clicking the map legend, hide & change to quest tab
	EventRegistry:RegisterCallback("ShowMapLegend", function()
		self.isMapLegend = true;
		self:SelectTab(WQT_TabNormal);
		WQT_WorldQuestFrame:ChangeAnchorLocation(_V["LIST_ANCHOR_TYPE"].world);
		WQT_TabNormal:Hide();
		WQT_TabWorld:Hide();
		QuestMapFrame.QuestsFrame.SearchBox:Hide(); -- ???
	end);
	EventRegistry:RegisterCallback("HideMapLegend", function()
		self.isMapLegend = false;
		self:SelectTab(WQT_TabNormal);
		WQT_WorldQuestFrame:ChangeAnchorLocation(_V["LIST_ANCHOR_TYPE"].world);
		QuestMapFrame.QuestsFrame.SearchBox:Show();
	end);
	
	-- Update when opening the map
	WorldMapFrame:HookScript("OnShow", function() 
			local mapAreaID = WorldMapFrame.mapID;
			self.dataProvider:LoadQuestsInZone(mapAreaID);
			self.ScrollFrame:UpdateQuestList();
			
			-- Prevent opening empty quest details
			local currentTab = self.selectedTab;
			if (currentTab == WQT_TabDetails and not QuestMapFrame.DetailsFrame.questID) then
				currentTab = WQT_TabNormal;
			end
			self:SelectTab(currentTab); 
			
			-- If emissaryOnly was automaticaly set, and there's none in the current list, turn it off again.
			if (WQT_WorldQuestFrame.autoEmissaryId and not WQT_WorldQuestFrame.dataProvider:ListContainsEmissary()) then
				WQT_WorldQuestFrame.autoEmissaryId = nil;
				WQT_QuestScrollFrame:UpdateQuestList();
			end
			
			-- Update worldquest button on first open, other addons might have added buttons...
			if not self.worldMapButtonSet then
				WQT_WorldQuestFrame:UpdateWorldMapButton();
				self.worldMapButtonSet = true;
			end
		end)

	-- Wipe data when hiding map
	WorldMapFrame:HookScript("OnHide", function() 
			self:HideOverlayFrame()
			wipe(WQT_QuestScrollFrame.questListDisplay);
			self.dataProvider:ClearData();
		end)

	-- Fix tabs when official quests are shown
	QuestScrollFrame:SetScript("OnShow", function() 
			--ElvUI fix
			if (QuestMapFrame.DetailsFrame:IsShown()) then
				self:SelectTab(WQT_TabDetails); 
				return;
			end
			
			if (self.selectedTab and self.selectedTab:GetID() == 2) then
				self:SelectTab(WQT_TabWorld); 
			else
				self:SelectTab(WQT_TabNormal); 
			end
		end)
		
	-- Re-anchor list when maxi/minimizing world map
	hooksecurefunc(WorldMapFrame, "HandleUserActionToggleSelf", function()
			if not WorldMapFrame:IsShown() then return end
			local anchor = WorldMapFramePortrait:IsShown() and _V["LIST_ANCHOR_TYPE"].world or _V["LIST_ANCHOR_TYPE"].full;
			WQT_WorldQuestFrame:ChangeAnchorLocation(anchor);
		end)

	hooksecurefunc(WorldMapFrame, "HandleUserActionToggleQuestLog", function()
			if not WorldMapFrame:IsShown() then return end
			local anchor = _V["LIST_ANCHOR_TYPE"].world;
			WQT_WorldQuestFrame:ChangeAnchorLocation(anchor);
		end)
	
	hooksecurefunc(WorldMapFrame, "HandleUserActionMinimizeSelf", function()
			WQT_WorldQuestFrame:ChangeAnchorLocation(_V["LIST_ANCHOR_TYPE"].world);
		end)
		
	hooksecurefunc(WorldMapFrame, "HandleUserActionMaximizeSelf", function()
			WQT_WorldQuestFrame:ChangeAnchorLocation(_V["LIST_ANCHOR_TYPE"].full);
		end)
		
	-- Opening quest details
	hooksecurefunc("QuestMapFrame_ShowQuestDetails", function(questID)
			self:SelectTab(WQT_TabDetails);
			if QuestMapFrame.DetailsFrame.questID == nil then
				QuestMapFrame.DetailsFrame.questID = questID;
			end
			-- Anchor to small map in case details were opened through clicking a quest in the obejctive tracker
			WQT_WorldQuestFrame:ChangeAnchorLocation(_V["LIST_ANCHOR_TYPE"].world);
		end)	
	
	-- Update our filters when changes are made to the world map filters
	local worldMapFilter;
	for k, frame in ipairs(WorldMapFrame.overlayFrames) do
		for name in pairs(frame) do
			if name == "SetupMenu" and IsDropdownButtonIntrinsic(frame) then
				worldMapFilter = frame;
				break;
			end
		end
	end
	if (worldMapFilter) then
		local function UpdateFilters()
			self.ScrollFrame:UpdateQuestList();
			WQT:UpdateFilterIndicator();
		end
		hooksecurefunc(worldMapFilter, "OnMenuResponse", function() UpdateFilters(); end);
		worldMapFilter.ResetButton:HookScript("OnClick", function() UpdateFilters(); end);
		self.worldMapFilter = worldMapFilter;
	end

	-- Auto emissary filter when clicking on one of the buttons
	local bountyBoard = WorldMapFrame.overlayFrames[_V["WQT_BOUNTYBOARD_OVERLAYID"]];
	self.bountyBoard = bountyBoard;
	
	hooksecurefunc(bountyBoard, "OnTabClick", function(self, tab) 
		if (not WQT.settings.general.autoEmissary or tab.isEmpty or WQT.settings.general.emissaryOnly) then return; end
		WQT_WorldQuestFrame.autoEmissaryId = bountyBoard.bounties[bountyBoard.selectedBountyIndex].questID;
		WQT_WorldQuestFrame.FilterButton:GenerateMenu(); --Update filter button
		WQT_QuestScrollFrame:UpdateQuestList();
	end)
	
	hooksecurefunc(bountyBoard, "RefreshSelectedBounty", function() 
		if (WQT.settings.general.bountyCounter) then
			self:UpdateBountyCounters();
		end
	end)
	
	-- Slight offset the tabs to make room for the counters
	hooksecurefunc(bountyBoard, "AnchorBountyTab", function(self, tab) 
		if (not WQT.settings.general.bountyCounter) then return end
		local point, relativeTo, relativePoint, x, y = tab:GetPoint(1);
		tab:SetPoint(point, relativeTo, relativePoint, x, y + 2);
	end)
	
	hooksecurefunc("TaskPOI_OnLeave", function(self)
			if (WQT.settings.pin.disablePoI) then return; end
			
			WQT_QuestScrollFrame.PoIHoverId = -1;
			WQT_QuestScrollFrame:UpdateQuestList(true);
			self.notTracked = nil;
		end)
		
	-- PVEFrame quest grouping
	LFGListFrame:HookScript("OnHide", function() 
			WQT_GroupSearch:Hide(); 
			WQT_GroupSearch.questID = nil;
			WQT_GroupSearch.title = nil;
		end)

	hooksecurefunc("LFGListSearchPanel_UpdateResults", function(self)
			if (self.searching and not InCombatLockdown()) then
				local searchString = LFGListFrame.SearchPanel.SearchBox:GetText();
				searchString = searchString:lower();
			
				if (WQT_GroupSearch.questID and WQT_GroupSearch.title and not (searchString:find(WQT_GroupSearch.questID) or WQT_GroupSearch.title:lower():find(searchString))) then
					WQT_GroupSearch.Text:SetText(_L["FORMAT_GROUP_TYPO"]:format(WQT_GroupSearch.questID, WQT_GroupSearch.title));
					WQT_GroupSearch:Show();
				else
					WQT_GroupSearch:Hide();
				end
			end
		end);
		
	LFGListFrame.EntryCreation:HookScript("OnHide", function() 
		if (not InCombatLockdown()) then
				WQT_GroupSearch:Hide();
			end
		end);
		
	hooksecurefunc("LFGListUtil_FindQuestGroup", function(questID, isFromGreenEyeButton)
		if (isFromGreenEyeButton) then
				WQT_GroupSearch:Hide();
				WQT_GroupSearch.questID = nil;
				WQT_GroupSearch.title = nil;
			end
		end);

	local LFGParent = LFGListFrame.SearchPanel.ScrollBox;
	if LFGParent and LFGParent.StartGroupButton then
		LFGParent.StartGroupButton:HookScript("OnClick", function() 
			-- If we are creating a group because we couldn't find one, show the info on the create frame
			if InCombatLockdown() then return; end
			local searchString = LFGListFrame.SearchPanel.SearchBox:GetText();
			searchString = searchString:lower();
			if (WQT_GroupSearch.questID and WQT_GroupSearch.title and (searchString:find(WQT_GroupSearch.questID) or WQT_GroupSearch.title:lower():find(searchString))) then
				WQT_GroupSearch.Text:SetText(_L["FORMAT_GROUP_CREATE"]:format(WQT_GroupSearch.questID, WQT_GroupSearch.title));
				WQT_GroupSearch:SetParent(LFGListFrame.EntryCreation.Name);
				WQT_GroupSearch:SetFrameLevel(LFGListFrame.EntryCreation.Name:GetFrameLevel()+5);
				WQT_GroupSearch:ClearAllPoints();
				WQT_GroupSearch:SetPoint("BOTTOMLEFT", LFGListFrame.EntryCreation.Name, "TOPLEFT", -2, 3);
				WQT_GroupSearch:SetPoint("BOTTOMRIGHT", LFGListFrame.EntryCreation.Name, "TOPRIGHT", -2, 3);
				WQT_GroupSearch.downArrow = true;
				WQT_GroupSearch.questID = nil;
				WQT_GroupSearch.title = nil;
				WQT_GroupSearch:Hide();
				WQT_GroupSearch:Show();
			end
		end)
	end
	-- Hook hiding of official pins if we replace them with our own
	local mapWQProvider = WQT_Utils:GetMapWQProvider();
	hooksecurefunc(mapWQProvider, "RefreshAllData", function() 
			self:HideOfficialMapPins();
		end);
		
	QuestMapFrame.QuestSessionManagement:HookScript("OnShow", function() 
			if(self:IsShown()) then
				QuestMapFrame.QuestSessionManagement:Hide();
			end
		end);

	-- Reduce SearchBox width to make room for the tabs
	local a,b,c,d,e = QuestMapFrame.QuestsFrame.SearchBox:GetPoint(1);
	QuestMapFrame.QuestsFrame.SearchBox:ClearAllPoints();
	QuestMapFrame.QuestsFrame.SearchBox:SetWidth(220);
	QuestMapFrame.QuestsFrame.SearchBox:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT", 0, e);
end

function WQT_CoreMixin:ApplyAllSettings()
	self:UpdateBountyCounters();
	self:RepositionBountyTabs();
	self.pinDataProvider:RefreshAllData()
	WQT_Utils:RefreshOfficialDataProviders();
	WQT_QuestScrollFrame:UpdateQuestList();
	WQT:Sort_OnClick(nil, WQT.settings.general.sortBy);
	WQT_WorldMapContainerButton:LinkSettings(WQT.settings.general.fullScreenButtonPos);
	WQT_WorldMapContainer:LinkSettings(WQT.settings.general.fullScreenContainerPos);
	WQT_WorldQuestFrame:UpdateWorldMapButton();
end

function WQT_CoreMixin:UpdateBountyCounters()
	self.bountyCounterPool:ReleaseAll();
	if (not WQT.settings.general.bountyCounter) then return end
	
	if (not self.bountyInfo) then
		self.bountyInfo = {};
	end
	
	local templates = self.bountyBoard.bountyTabPool:EnumerateActive();
	for activePin in templates do
		self:AddBountyCountersToTab(activePin);
	end
end

function WQT_CoreMixin:RepositionBountyTabs()
	local templates = self.bountyBoard.bountyTabPool:EnumerateActive();
	for activePin in templates do
		self.bountyBoard:AnchorBountyTab(activePin);
	end
end

function WQT_CoreMixin:AddBountyCountersToTab(tab)
	local settingBountyReward = WQT_Utils:GetSetting("general", "bountyReward");

	if (not tab.WQT_Reward) then
		tab.WQT_Reward = CreateFrame("FRAME", nil, tab, "WQT_MiniIconTemplate");
		tab.WQT_Reward:SetPoint("CENTER", tab, "TOPRIGHT", -8, -7);
	end
	tab.WQT_Reward:Reset();
	
	local bountyData = self.bountyBoard.bounties[tab.bountyIndex];
	
	if (bountyData) then
		local progress, goal = self.bountyBoard:CalculateBountySubObjectives(bountyData);
		
		if (progress == goal) then return end;
		
		-- RewardIcon
		if (settingBountyReward) then
			local bountyQuestInfo = self.bountyInfo[bountyData.questID];
			if (not bountyQuestInfo) then
				bountyQuestInfo = WQT_Utils:QuestCreationFunc();
				self.bountyInfo[bountyData.questID] = bountyQuestInfo;
				bountyQuestInfo:Init(bountyData.questID);
			end
			bountyQuestInfo:LoadRewards();
			tab.WQT_Reward:SetupRewardIcon(bountyQuestInfo:GetFirstNoneAzeriteType());
			tab.WQT_Reward:SetScale(1.38);
		end
		
		-- Counters
		local offsetAngle = 32;
		local startAngle = 270;
		
		-- position of first counter
		startAngle = startAngle - offsetAngle * (goal -1) /2
		
		for i=1, goal do
			local counter = self.bountyCounterPool:Acquire();

			local x = cos(startAngle) * 16;
			local y = sin(startAngle) * 16;
			counter:SetPoint("CENTER", tab.Icon, "CENTER", x, y);
			counter:SetParent(tab);
			counter:Show();
			
			-- Light nr of completed
			if i <= progress then
				counter.icon:SetTexCoord(0, 0.5, 0, 0.5);
				counter.icon:SetVertexColor(1, 1, 1, 1);
				counter.icon:SetDesaturated(false);
			else
				counter.icon:SetTexCoord(0, 0.5, 0, 0.5);
				counter.icon:SetVertexColor(0.75, 0.75, 0.75, 1);
				counter.icon:SetDesaturated(true);
			end

			-- Offset next counter
			startAngle = startAngle + offsetAngle;
		end
	end
	
end

function WQT_CoreMixin:UpdateWorldMapButton()
	local alignButton = WQT.settings.general.alignWorldMapButton;
	if alignButton then
		-- Get all the frames
		local frames = {WorldMapFrame:GetChildren();}
		local framesCount = WorldMapFrame:GetNumChildren();
		if framesCount > 0 then
			local topRightButtonPoolXOffset = -4;
			local topRightButtonPoolXOffsetAmount = -32;
			
			for i, frame in ipairs(frames) do
				if frame:GetObjectType() == "Button" then
					local point, relativeTo, relativePoint, offsetX, offsetY = frame:GetPoint(1);
					
					-- Iterate through the top right buttons
					if offsetY == -2 and offsetX == topRightButtonPoolXOffset then
						topRightButtonPoolXOffset = topRightButtonPoolXOffset + topRightButtonPoolXOffsetAmount;
					end
				end
			end
			
			WQT_WorldMapContainerButton:ClearAllPoints();
			WQT_WorldMapContainerButton:SetMovable(false);
			WQT_WorldMapContainerButton:SetPoint("TOPRIGHT", WorldMapFrame.ScrollContainer, "TOPRIGHT", topRightButtonPoolXOffset, -2);
		end
	else
		WQT_WorldMapContainerButton:SetMovable(true);
		WQT_WorldMapContainerButton:LinkSettings(WQT.settings.general.fullScreenButtonPos);
	end
end

function WQT_CoreMixin:ShowHighlightOnMapFilters()
	if (not self.worldMapFilter) then return; end
	WQT_PoISelectIndicator:SetParent(self.worldMapFilter);
	WQT_PoISelectIndicator:ClearAllPoints();
	WQT_PoISelectIndicator:SetPoint("CENTER", self.worldMapFilter, 0, 1);
	WQT_PoISelectIndicator:SetFrameLevel(self.worldMapFilter:GetFrameLevel()+1);
	WQT_PoISelectIndicator:Show();
	local size = WQT.settings.pin.bigPoI and 50 or 40;
	WQT_PoISelectIndicator:SetSize(size, size);
	WQT_PoISelectIndicator:SetScale(0.40);
end

function WQT_CoreMixin:FilterClearButtonOnClick()
	if WQT_WorldQuestFrame.autoEmissaryId then
		WQT_WorldQuestFrame.autoEmissaryId = nil;
	elseif WQT.settings.general.emissaryOnly then
		WQT.settings.general.emissaryOnly = false;
	else
		for k, v in pairs(WQT.settings.filters) do
			local default = not WQT.settings.general.preciseFilters;
			WQT:SetAllFilterTo(k, default);
		end
	end
	
	WQT.settings.general.showDisliked = true;
	
	WQT_QuestScrollFrame:UpdateQuestList();
end

function WQT_CoreMixin:SearchGroup(questInfo)
	local id, title;
	if (type(questInfo) == "number") then
		id = questInfo;
	else
		id = questInfo.questID;
	end
	title = C_TaskQuest.GetQuestInfoByQuestID(id);
	
	WQT_GroupSearch:Hide();
	LFGListUtil_FindQuestGroup(id);
	
	-- If we can't automatically make a group, show a message on what the player should type
	if (not C_LFGList.CanCreateQuestGroup(id)) then
		WQT_GroupSearch:SetParent(LFGListFrame.SearchPanel.SearchBox);
		WQT_GroupSearch:SetFrameLevel(LFGListFrame.SearchPanel.SearchBox:GetFrameLevel()+5);
		WQT_GroupSearch:ClearAllPoints();
		WQT_GroupSearch:SetPoint("TOPLEFT", LFGListFrame.SearchPanel.SearchBox, "BOTTOMLEFT", -2, -3);
		WQT_GroupSearch:SetPoint("RIGHT", LFGListFrame.SearchPanel.SearchBox, "RIGHT", -30, 0);
	
		WQT_GroupSearch.Text:SetText(_L["FORMAT_GROUP_SEARCH"]:format(id, title));
		WQT_GroupSearch.downArrow = false;
		WQT_GroupSearch:Hide();
		WQT_GroupSearch:Show();
		
		WQT_GroupSearch.questID = id;
		WQT_GroupSearch.title = title;
	end
end

-- Only allow LFG for quests that would actually allow it
function WQT_CoreMixin:ShouldAllowLFG(questInfo)
	if (not questInfo) then return false; end

	local tagInfo;
	if (type(questInfo) == "number") then
		tagInfo = C_QuestLog.GetQuestTagInfo(questInfo);
	else
		if (questInfo.isDaily) then 
			return false; 
		end
		tagInfo = questInfo:GetTagInfo();
	end
	
	return tagInfo and tagInfo.worldQuestType and not (tagInfo.worldQuestType == Enum.QuestTagType.PetBattle or tagInfo.worldQuestType == Enum.QuestTagType.Dungeon or tagInfo.worldQuestType == Enum.QuestTagType.Progession or tagInfo.worldQuestType == Enum.QuestTagType.Raid);
end

function WQT_CoreMixin:UnhookEvent(event, func)
	local list = self.eventHooks[event];
	if (list) then
		list[func] = nil;
	end
end

function WQT_CoreMixin:ADDON_LOADED(loaded)
	WQT:UpdateFilterIndicator();
	if (loaded == "Blizzard_FlightMap") then
		-- Hook official pins to hide on show
		-- I'd rather not do it this way but the Flight map pins update so much I might as well
		local flightWQProvider = WQT_Utils:GetFlightWQProvider();
		hooksecurefunc(flightWQProvider, "AddWorldQuest", function(frame, info) 
				local flightMapTemplate = FlightMapFrame.pinPools[FlightMap_WorldQuestDataProviderMixin:GetPinTemplate()];
				if flightMapTemplate then
					local pool = flightMapTemplate:EnumerateActive();
					for pin in pool do
						if not pin.WQTHooked then
							pin.WQTHooked = true;
							pin:HookScript("OnShow", function() 
								self:TryHideOfficialMapPin(pin);
							end);
						end
					end
				end
			end);
		
		WQT_FlightMapContainer:SetParent(FlightMapFrame);
		WQT_FlightMapContainer:SetPoint("BOTTOMLEFT", FlightMapFrame, "BOTTOMRIGHT", -6, 0);
		WQT_FlightMapContainerButton:SetParent(FlightMapFrame);
		WQT_FlightMapContainerButton:SetAlpha(1);
		WQT_FlightMapContainerButton:SetPoint("BOTTOMRIGHT", FlightMapFrame, "BOTTOMRIGHT", -8, 8);
		WQT_FlightMapContainerButton:SetFrameLevel(FlightMapFrame:GetFrameLevel()+2);
	elseif (loaded == "WorldFlightMap") then
		_WFMLoaded = true;
	--elseif (loaded == "WorldQuestTabUtilities") then
	--	WQT.settings.general.loadUtilities = true;
	end
	
	-- Load waiting externals
	if (WQT.loadableExternals) then
		local external = WQT.loadableExternals[loaded];
		if (external) then
			external:Init(WQT_Utils);
			WQT:debugPrint("External", external:GetName(), "delayed load.");
			WQT.loadableExternals[loaded] = nil;
		end
	end
end

function WQT_CoreMixin:PLAYER_REGEN_DISABLED()
	-- Custom LFG buttons disabled during combat, because the LFG frame is protected
	if ObjectiveTrackerBlocksFrame == nil then
		return
	end
	for k, block in ipairs({ObjectiveTrackerBlocksFrame:GetChildren()}) do
		if (block.WQTButton) then
			block.WQTButton:SetEnabled(false);
		end
	end
end

function WQT_CoreMixin:PLAYER_REGEN_ENABLED()
	-- Custom LFG buttons disabled during combat, because the LFG frame is protected
	if ObjectiveTrackerBlocksFrame == nil then
		return
	end
	for k, block in ipairs({ObjectiveTrackerBlocksFrame:GetChildren()}) do
		if (block.WQTButton) then
			block.WQTButton:SetEnabled(true);
		end
	end
end

function WQT_CoreMixin:QUEST_TURNED_IN(questID)
	local questInfo = WQT_WorldQuestFrame.dataProvider:GetQuestById(questID);
	if (questInfo) then
		WQT_WorldQuestFrame:TriggerCallback("WorldQuestCompleted", questID, questInfo);
	end
end

 -- Warmode toggle because WAR_MODE_STATUS_UPDATE doesn't seems to fire when toggling warmode
function WQT_CoreMixin:PVP_TIMER_UPDATE()
	self.ScrollFrame:UpdateQuestList();
end

function WQT_CoreMixin:WORLD_QUEST_COMPLETED_BY_SPELL()
	self.ScrollFrame:UpdateQuestList();
end

function WQT_CoreMixin:PLAYER_LOGOUT()
	WQT_Profiles:ClearDefaultsFromActive();
end

function WQT_CoreMixin:QUEST_WATCH_LIST_CHANGED(...)
	self.ScrollFrame:DisplayQuestList();
end

function WQT_CoreMixin:TAXIMAP_OPENED(system)
	local anchor = _V["LIST_ANCHOR_TYPE"].taxi;
	if (system == 2) then
		-- It's the new flight map
		anchor = _V["LIST_ANCHOR_TYPE"].flight;
	end
	
	WQT_WorldQuestFrame:ChangeAnchorLocation(anchor);
	self.dataProvider:LoadQuestsInZone(FlightMapFrame and FlightMapFrame:GetMapID() or GetTaxiMapID());
end

-- Reset official map filters
function WQT_CoreMixin:SetCvarValue(flagKey, value)
	value = (value == nil) and true or value;

	if _V["WQT_CVAR_LIST"][flagKey] then
		SetCVar(_V["WQT_CVAR_LIST"][flagKey], value);
		self.ScrollFrame:UpdateQuestList();
		WQT:UpdateFilterIndicator();
		return true;
	end
	return false;
end

-- Show a frame over the world quest list
function WQT_CoreMixin:ShowOverlayFrame(frame)
	if (not frame) then return end

	local blocker = self.Blocker;
	-- Hide the previous frame if any
	if (blocker.CurrentOverlayFrame) then
		self:HideOverlayFrame();
	end
	blocker.CurrentOverlayFrame = frame;
	
	blocker:Show();
	self:SetCustomEnabled(false);
	
	frame:SetParent(blocker);
	frame:SetFrameLevel(blocker:GetFrameLevel()+1)
	frame:SetFrameStrata(blocker:GetFrameStrata())
	frame:Show();

	self.manualCloseOverlay = true;

	-- Hide little gear icon
	self.SettingsButton:Hide();
	QuestMapFrame.SettingsDropdown:Hide();

	-- Hide quest and filter to prevent bleeding through when walking around
	WQT_QuestScrollFrame:Hide();
end

function WQT_CoreMixin:HideOverlayFrame()
	local blocker = self.Blocker;
	if (not blocker.CurrentOverlayFrame) then return end
	self:SetCustomEnabled(true);
	blocker:Hide();
	blocker.CurrentOverlayFrame:Hide();
	blocker.CurrentOverlayFrame = nil;

	-- Show little gear icon
	self.SettingsButton:Show();
	QuestMapFrame.SettingsDropdown:Show();

	-- Show everything again
	WQT_QuestScrollFrame:Show();
end

-- Enable/Disable all world quest list functionality
function WQT_CoreMixin:SetCustomEnabled(value)
	value = value==nil and true or value;
	
	self:EnableMouse(value);
	self:EnableMouseWheel(value);
	WQT_QuestScrollFrame:EnableMouseWheel(value);
	WQT_QuestScrollFrame:EnableMouse(value);
	WQT_QuestScrollFrame.ScrollBar:EnableMouseWheel(value);
	WQT_QuestScrollFrame.ScrollBar:EnableMouse(value);
	if value then
		self.FilterButton:Enable();
		self.SortDropdown:Enable();
		self.SettingsButton:Enable();
	else
		self.FilterButton:Disable();
		self.SortDropdown:Disable();
		self.SettingsButton:Disable();
	end

	self.ScrollFrame:SetButtonsEnabled(value);
	self.ScrollFrame:EnableMouseWheel(value);
end

function WQT_CoreMixin:SelectTab(tab)
	
	local id = tab and tab:GetID() or 0;
	if self.selectedTab ~= tab then
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
		WQT_WorldQuestFrame.pinDataProvider:RefreshAllData();
	end
	self.selectedTab = tab;
	if not self.isMapLegend then
		WQT_TabNormal:Show();
		WQT_TabWorld:Show();
	end
	WQT_TabNormal:SetFrameLevel(2);
	WQT_TabWorld:SetFrameLevel(2);
	WQT_TabNormal.Hider:Show();
	WQT_TabWorld.Hider:Show();

	-- Hide/show when quest details are shown
	QuestMapFrame_UpdateQuestSessionState(QuestMapFrame);
	self:HideOverlayFrame();
	
	-- Move quest window down, making space for tabs
	local a,b,c,d = QuestMapFrame:GetPoint(1);
	QuestMapFrame:SetPoint(a,b,c,d,-35);
		
	if (not QuestScrollFrame.Contents:IsShown() and not QuestMapFrame.DetailsFrame:IsShown()) or id == 1 then
		-- Default questlog
		self:Hide();
		WQT_TabNormal:SetFrameLevel(10);
		WQT_TabNormal.Hider:Hide();
		WQT_TabNormal.Highlight:Show();
		WQT_TabNormal.TabBg:SetTexCoord(0.01562500, 0.79687500, 0.78906250, 0.95703125);
		WQT_TabWorld.TabBg:SetTexCoord(0.01562500, 0.79687500, 0.61328125, 0.78125000);
		QuestScrollFrame:Show();
	elseif id == 2 then
		-- WQT
		WQT_TabWorld:SetFrameLevel(10);
		WQT_TabWorld.Hider:Hide();
		WQT_TabWorld.Highlight:Show();
		self:Show();
		WQT_TabWorld.TabBg:SetTexCoord(0.01562500, 0.79687500, 0.78906250, 0.95703125);
		WQT_TabNormal.TabBg:SetTexCoord(0.01562500, 0.79687500, 0.61328125, 0.78125000);
		QuestScrollFrame:Hide();
		-- Prevent the party sync block from showing through the quest list. 
		QuestMapFrame.QuestSessionManagement:Hide();
	elseif id == 3 then
		-- Quest details
		self:Hide();
		WQT_TabNormal:Hide();
		WQT_TabWorld:Hide()
		QuestScrollFrame:Hide();
		QuestMapFrame.DetailsFrame:Show();
		
		-- Move quest window up if a quest is showing
		local a,b,c,d = QuestMapFrame:GetPoint(1);
		QuestMapFrame:SetPoint(a,b,c,d,-25);
	end
	
	WQT_QuestLogFiller:UpdateVisibility();
end

function WQT_CoreMixin:ChangeAnchorLocation(anchor)
	-- Store the original tab for when we come back to the world anchor
	if (self.anchor == _V["LIST_ANCHOR_TYPE"].world) then
		self.tabBeforeAnchor = self.selectedTab;
	end
	
	-- Prevent showing up when the map is minimized
	if (anchor ~= _V["LIST_ANCHOR_TYPE"].full) then
		WQT_WorldMapContainer:Hide();
	end
	
	if (not anchor) then
		WQT_WorldQuestFrame:SetParent(QuestMapFrame);
		WQT_WorldQuestFrame:SetPoint("TOPLEFT", parent, 3, -10);
		WQT_WorldQuestFrame:SetPoint("BOTTOMRIGHT", parent, -8, 3);
		WQT_WorldQuestFrame:SelectTab(WQT_TabWorld);
		return
	end
	
	self.anchor = anchor;
	
	local parent = QuestMapFrame;
	local point =  "BOTTOMLEFT";
	local xOffset = 3;
	local yOffset = 5;
	local tab = WQT_TabWorld;
	
	if (anchor == _V["LIST_ANCHOR_TYPE"].flight) then
		parent = WQT_FlightMapContainer;
		
		WQT_WorldQuestFrame:ClearAllPoints();
		WQT_WorldQuestFrame:SetParent(parent);
		WQT_WorldQuestFrame:SetPoint("TOPLEFT", parent, 3, -10);
		WQT_WorldQuestFrame:SetPoint("BOTTOMRIGHT", parent, -8, 3);
		WQT_WorldQuestFrame:SelectTab(tab);
		
		WQT_WorldQuestFrame:TriggerCallback("AnchorChanged", anchor);
		return;
	elseif (anchor == _V["LIST_ANCHOR_TYPE"].taxi) then
		parent = WQT_OldTaxiMapContainer;
	elseif (anchor == _V["LIST_ANCHOR_TYPE"].world) then
		point = "TOPLEFT";
		tab = self.tabBeforeAnchor;
		WQT_WorldMapContainer:Hide();
		WQT_WorldMapContainerButton:Hide();
		
		WQT_WorldQuestFrame:ClearAllPoints(); 
		WQT_WorldQuestFrame:SetParent(parent);
		WQT_WorldQuestFrame:SetPoint("TOPLEFT", QuestMapFrame, -3, 7);
		WQT_WorldQuestFrame:SetPoint("BOTTOMRIGHT", QuestMapFrame);
		WQT_WorldQuestFrame:SelectTab(tab);
		
		WQT_WorldQuestFrame:TriggerCallback("AnchorChanged", anchor);
		return
	elseif (anchor == _V["LIST_ANCHOR_TYPE"].full) then
		parent = WQT_WorldMapContainer;
		WQT_WorldMapContainer:ConstrainPosition();
		WQT_WorldMapContainerButton:ConstrainPosition();
		WQT_WorldQuestFrame:SetFrameLevel(WQT_WorldMapContainer:GetFrameLevel()+2);
		WQT_WorldMapContainerButton:Show();
		WQT_WorldMapContainer:SetShown(WQT_WorldMapContainerButton.isSelected);
		
		WQT_WorldQuestFrame:ClearAllPoints();
		WQT_WorldQuestFrame:SetParent(parent);
		WQT_WorldQuestFrame:SetPoint("TOPLEFT", parent, 3, -10);
		WQT_WorldQuestFrame:SetPoint("BOTTOMRIGHT", parent, -8, 3);
		WQT_WorldQuestFrame:SelectTab(tab);
		
		WQT_WorldQuestFrame:TriggerCallback("AnchorChanged", anchor);
		return
	end

	WQT_WorldQuestFrame:ClearAllPoints();
	WQT_WorldQuestFrame:SetParent(parent);
	WQT_WorldQuestFrame:SetPoint(point, parent, point, xOffset, yOffset);
	WQT_WorldQuestFrame:SelectTab(tab);
	WQT_WorldQuestFrame:TriggerCallback("AnchorChanged", anchor);
end

function WQT_CoreMixin:LoadExternal(external)
	if (self.isEnabled and external:IsLoaded()) then
		external:Init(WQT_Utils);
	else
		tinsert(addon.externals, external);
	end
end


