﻿local addonName, addon = ...

local BWQ = LibStub("AceAddon-3.0"):NewAddon("WorldQuestTab");

-- 1007 Broken Isles
local _legionZoneIds = {1014, 1015, 1033, 1017, 1024, 1018, 1096};

local _zoneCoords = {
		 [1015] = {["x"] = 0.33, ["y"] = 0.58} -- Azsuna
		,[1033] = {["x"] = 0.46, ["y"] = 0.45} -- Suramar
		,[1017] = {["x"] = 0.60, ["y"] = 0.33} -- Stormheim
		,[1024] = {["x"] = 0.46, ["y"] = 0.23} -- Highmountain
		,[1018] = {["x"] = 0.34, ["y"] = 0.33} -- Val'sharah
		,[1096] = {["x"] = 0.46, ["y"] = 0.84} -- Eye of Azshara
	}

local _completedQuest = false;
local _questTitle = "Uniting the Isles"
local _questList = {};
local _questPool = {};
local _questDisplayList = {};
local _questsMissingReward = {};
local _sortOptions = {[1] = "Time", [2] = "Faction", [3] = "Type", [4] = "Zone", [5] = "Name", [6] = "Reward"}
local _artifactSpells = {
		 "Empowering" -- ENG
		,"Macht verleihen" -- DE
		,"Potenciando" -- ESP
		,"Fortalecendo" -- PT
		,"Renforcement" -- FR
		,"Potenziamento" -- IT
		,"Усиление" -- RU
	}
local _factionIcons = {
	 [1894] = "Interface/ICONS/INV_LegionCircle_Faction_Warden"
	,[1859] = "Interface/ICONS/INV_LegionCircle_Faction_NightFallen"
	,[1900] = "Interface/ICONS/INV_LegionCircle_Faction_CourtofFarnodis"
	,[1948] = "Interface/ICONS/INV_LegionCircle_Faction_Valarjar"
	,[1828] = "Interface/ICONS/INV_LegionCircle_Faction_HightmountainTribes"
	,[1883] = "Interface/ICONS/INV_LegionCircle_Faction_DreamWeavers"
	,[1090] = "Interface/ICONS/INV_LegionCircle_Faction_KirinTor"
}
local _filterOrders = {}
local _defaults = {
	global = {	
		defaultTab = false;
		showTypeIcon = true;
		showFactionIcon = true;
		saveFilters = false;
		filterPoI = false;
		--defaultPoI = false;
		showPinReward = true;
		showPinTime = true;
		sortBy = 1;
		filters = {
				[1] = {["name"] = "Faction"
				, ["flags"] = {[GetFactionInfoByID(1859)] = false, [GetFactionInfoByID(1894)] = false, [GetFactionInfoByID(1828)] = false, [GetFactionInfoByID(1883)] = false
								, [GetFactionInfoByID(1948)] = false, [GetFactionInfoByID(1900)] = false, [GetFactionInfoByID(1090)] = false}}
				,[2] = {["name"] = "Type"
						, ["flags"] = {["Default"] = false, ["Elite"] = false, ["PvP"] = false, ["Petbattle"] = false, ["Dungeon"] = false, ["Profession"] = false, ["Emissary"] = false}}
				,[3] = {["name"] = "Reward"
						, ["flags"] = {["Item"] = false, ["Armor"] = false, ["Gold"] = false, ["Resources"] = false, ["Artifact"] = false, }}
			}
	}
}
local functionCalls = {};

local BWQ_REWARDTYPE_ITEM = 3;
local BWQ_REWARDTYPE_GOLD = 4;
local BWQ_REWARDTYPE_CURRENCY = 5;
local BWQ_REWARDTYPE_ARMOR = 1;
local BWQ_REWARDTYPE_ARTIFACT = 2;
local BWQ_COMBATLOCK = "Disabled during combat.";
local BWQ_NOT_HERE = "You can't view world quests here.";
local BWQ_FILTERS = "Filters: %s";
local BWQ_SORT_BY = "By %s";
local BWQ_UNLOCK_110 = "Unlocked at\nlevel 110."
local BWQ_UNLOCK_QUEST = "Complete quest:\n%s";
local BWQ_WHITE_FONT_COLOR = CreateColor(0.8, 0.8, 0.8);
local BWQ_ORANGE_FONT_COLOR = CreateColor(1, 0.6, 0);
local BWQ_GREEN_FONT_COLOR = CreateColor(0, 0.75, 0);
local BWQ_BLUE_FONT_COLOR = CreateColor(0.1, 0.68, 1);
local BWQ_LISTITTEM_HEIGHT = 32;
local BWQ_REFRESH_DEFAULT = 60;
local BWQ_REFRESH_FAST = 0.5;
local BWQ_REFRESH_LIMIT = 5;
local BWQ_REFRESH_FAIL = "[WQT] No reward info more than " .. BWQ_REFRESH_LIMIT .. " times in a row. Ending fast refresh."
local BWQ_QUESTIONMARK = "Interface/ICONS/INV_Misc_QuestionMark";

------------------------------------------------------------

function BWQ:ScrollFrameSetEnabled(enabled)

	BWQ_WorldQuestFrame:EnableMouse(enabled)
	BWQ_QuestScrollFrame:EnableMouse(enabled);
	BWQ_QuestScrollFrame:EnableMouseWheel(enabled);
	local buttons = BWQ_QuestScrollFrame.buttons;
	for k, button in ipairs(buttons) do
		button:EnableMouse(enabled);
	end
end

function BWQ_Tab_Onclick(self, button)
	if(button == "RightButton") then
		BWQ:UpdateQuestList();
	end

	--if InCombatLockdown() then return end
	id = self and self:GetID() or nil;
	BWQ_WorldQuestFrame.selectedTab = self;
	
	BWQ_TabNormal:SetAlpha(1);
	BWQ_TabWorld:SetAlpha(1);
	-- because being able to hide shit in combat would be too usefull
	if not InCombatLockdown() then
		BWQ_TabNormal:SetFrameLevel(BWQ_TabNormal:GetParent():GetFrameLevel()+(self == BWQ_TabNormal and 1 or 0));
		BWQ_TabWorld:SetFrameLevel(BWQ_TabWorld:GetParent():GetFrameLevel()+(self == BWQ_TabWorld and 1 or 0));
	 
		BWQ_WorldQuestFrameFilterButton:SetFrameLevel(BWQ_WorldQuestFrameFilterButton:GetParent():GetFrameLevel());
		BWQ_WorldQuestFrameSortButton:SetFrameLevel(BWQ_WorldQuestFrameSortButton:GetParent():GetFrameLevel());
		
		BWQ_WorldQuestFrame:SetFrameLevel(0);
	end
	
	
	if (not QuestScrollFrame.Contents:IsShown() and not QuestMapFrame.DetailsFrame:IsShown()) or id == 1 then
		BWQ_WorldQuestFrame:SetAlpha(0);
		BWQ_TabNormal.Highlight:Show();
		BWQ_TabNormal.TabBg:SetTexCoord(0.01562500, 0.79687500, 0.78906250, 0.95703125);
		BWQ_TabWorld.TabBg:SetTexCoord(0.01562500, 0.79687500, 0.61328125, 0.78125000);
		ShowUIPanel(QuestScrollFrame);
		if not InCombatLockdown() then
			BWQ:ScrollFrameSetEnabled(false)
		end
	elseif id == 2 then
		BWQ_TabWorld.Highlight:Show();
		BWQ_WorldQuestFrame:SetAlpha(1);
		BWQ_TabWorld.TabBg:SetTexCoord(0.01562500, 0.79687500, 0.78906250, 0.95703125);
		BWQ_TabNormal.TabBg:SetTexCoord(0.01562500, 0.79687500, 0.61328125, 0.78125000);
		HideUIPanel(QuestScrollFrame);
		if not InCombatLockdown() then
			BWQ_WorldQuestFrame:SetFrameLevel(BWQ_WorldQuestFrame:GetParent():GetFrameLevel()+3);
			BWQ:ScrollFrameSetEnabled(true)
		end
	elseif id == 3 then
		BWQ_WorldQuestFrame:SetAlpha(0);
		BWQ_TabNormal:SetAlpha(0);
		BWQ_TabWorld:SetAlpha(0);
		HideUIPanel(QuestScrollFrame);
		BWQ_TabNormal:SetFrameLevel(BWQ_TabNormal:GetParent():GetFrameLevel()-1);
		BWQ_TabWorld:SetFrameLevel(BWQ_TabWorld:GetParent():GetFrameLevel()-1);
		BWQ_WorldQuestFrameFilterButton:SetFrameLevel(0);
		BWQ_WorldQuestFrameSortButton:SetFrameLevel(0);
	end
end

function BWQ_Quest_OnClick(self, button)
	PlaySound("igMainMenuOptionCheckBoxOn");
	if not self.questId or self.questId== -1 then return end
	if IsShiftKeyDown() then
		if IsWorldQuestHardWatched(self.questId) or (IsWorldQuestWatched(self.questId) and GetSuperTrackedQuestID() == self.questId) then
			BonusObjectiveTracker_UntrackWorldQuest(self.questId);
		else
			BonusObjectiveTracker_TrackWorldQuest(self.questId, true);
		end
	elseif button == "LeftButton" then
		if IsWorldQuestHardWatched(self.questId) then
			SetSuperTrackedQuestID(self.questId);
		else
			BonusObjectiveTracker_TrackWorldQuest(self.questId);
		end
		SetMapByID(self.zoneId or 1007);
	elseif button == "RightButton" then
		if BWQ_TrackDropDown:GetParent() == self then
			Lib_ToggleDropDownMenu(1, nil, BWQ_TrackDropDown, "cursor", -10, -10);
		else
			BWQ_TrackDropDown:SetParent(self);
			Lib_HideDropDownMenu(1);
			Lib_ToggleDropDownMenu(1, nil, BWQ_TrackDropDown, "cursor", -10, -10);
		end
	end
	
	BWQ:DisplayQuestList();
end

function BWQ_Quest_OnEnter(self)
	WorldMapTooltip:SetOwner(self, "ANCHOR_RIGHT");
	
	if IsModifiedClick("COMPAREITEMS") or GetCVarBool("alwaysCompareItems") then
		GameTooltip_ShowCompareItem(WorldMapTooltip.ItemTooltip.Tooltip, WorldMapTooltip.BackdropFrame);
	else
		for i, tooltip in ipairs(WorldMapTooltip.ItemTooltip.Tooltip.shoppingTooltips) do
			tooltip:Hide();
		end
	end
	
	local i = 1;
	local button = _G["WorldMapFrameTaskPOI"..i]
	while(button) do
		if button.questID == self.questId then
			BWQ_PoISelectIndicator:SetParent(button);
			BWQ_PoISelectIndicator:ClearAllPoints();
			BWQ_PoISelectIndicator:SetPoint("CENTER", button);
			BWQ_PoISelectIndicator:SetFrameLevel(button:GetFrameLevel()+1);
			BWQ_PoISelectIndicator:Show();
		end
		i = i + 1;
		button = _G["WorldMapFrameTaskPOI"..i]
	end
	
	if ( not HaveQuestData(self.questId) ) then
		WorldMapTooltip:SetText(RETRIEVING_DATA, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b);
		WorldMapTooltip:Show();
		return;
	end
	
	if self.info.rewardTexture == BWQ_QUESTIONMARK then
		BWQ:SetQuestReward(self.info)
	end
	self.reward.icon:SetTexture(self.info.rewardTexture);

	local title, factionID, capped = C_TaskQuest.GetQuestInfoByQuestID(self.questId);
		local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex = GetQuestTagInfo(self.questId);
		local color = WORLD_QUEST_QUALITY_COLORS[rarity];
		WorldMapTooltip:SetText(title, color.r, color.g, color.b);

		if ( factionID ) then
			local factionName = GetFactionInfoByID(factionID);
			if ( factionName ) then
				if (capped) then
					WorldMapTooltip:AddLine(factionName, GRAY_FONT_COLOR:GetRGB());
				else
					WorldMapTooltip:AddLine(factionName);
				end
			end
		end

		WorldMap_AddQuestTimeToTooltip(self.questId);

	for objectiveIndex = 1, self.numObjectives do
		local objectiveText, objectiveType, finished = GetQuestObjectiveInfo(self.questId, objectiveIndex, false);
		if ( objectiveText and #objectiveText > 0 ) then
			local color = finished and GRAY_FONT_COLOR or HIGHLIGHT_FONT_COLOR;
			WorldMapTooltip:AddLine(QUEST_DASH .. objectiveText, color.r, color.g, color.b, true);
		end
	end

	local percent = C_TaskQuest.GetQuestProgressBarInfo(self.questId);
	if ( percent ) then
		GameTooltip_InsertFrame(WorldMapTooltip, WorldMapTaskTooltipStatusBar);
		WorldMapTaskTooltipStatusBar.Bar:SetValue(percent);
		WorldMapTaskTooltipStatusBar.Bar.Label:SetFormattedText(PERCENTAGE_STRING, percent);
	end

	WorldMap_AddQuestRewardsToTooltip(self.questId);
	
	-- Add debug lines
	-- for k, v in pairs(self.info)do
		-- WorldMapTooltip:AddDoubleLine(k, type(v) == "boolean" and (v and "true" or "false") or v);
	-- end
	
	WorldMapTooltip:Show();
	
	BWQ:ShowWorldmapHighlight(self.info.zoneId);
end

function BWQ:ShowWorldmapHighlight(zoneId)

	if GetCurrentMapAreaID() ~= 1007 or not _zoneCoords[zoneId] then return; end
	local adjustedX, adjustedY = _zoneCoords[zoneId].x, _zoneCoords[zoneId].y;
	local width = WorldMapButton:GetWidth();
	local height = WorldMapButton:GetHeight();
	
	local name, fileName, texPercentageX, texPercentageY, textureX, textureY, scrollChildX, scrollChildY, minLevel, maxLevel, petMinLevel, petMaxLevel = UpdateMapHighlight( adjustedX, adjustedY );
	
	if ( fileName ) then
		BWQ_MapZoneHightlight.texture:SetTexCoord(0, texPercentageX, 0, texPercentageY);
		BWQ_MapZoneHightlight.texture:SetTexture("Interface\\WorldMap\\"..fileName.."\\"..fileName.."Highlight");
		textureX = textureX * width;
		textureY = textureY * height;
		scrollChildX = scrollChildX * width;
		scrollChildY = -scrollChildY * height;
		if ( (textureX > 0) and (textureY > 0) ) then
			BWQ_MapZoneHightlight:SetWidth(textureX);
			BWQ_MapZoneHightlight:SetHeight(textureY);
			BWQ_MapZoneHightlight:SetPoint("TOPLEFT", "WorldMapDetailFrame", "TOPLEFT", scrollChildX, scrollChildY);
			BWQ_MapZoneHightlight:Show();
			WorldMapFrameAreaLabel:SetText(name)
		end
	end
end

local function GetAbreviatedNumber(number)
	if type(number) ~= "number" then return "NaN" end;
	if (number >= 1000 and number < 10000) then
		local rest = number - floor(number/1000)*1000
		if rest < 100 then
			return floor(number / 1000) .. "k";
		else
			return floor(number / 100)/10 .. "k";
		end
	elseif (number >= 10000) then
		return floor(number / 1000) .. "k";
	end

	return number 
end

local function GetQuestFromList(id)
	for k, quest in pairs(_questList) do
		if quest.id == id then return quest; end
	end
	return nil;
end

local function IsArtifactItem(itemId)
	local spell = GetItemSpell(itemId)
	for k, v in ipairs(_artifactSpells) do
		if v == spell then return true; end
	end
	return false;
end

local function ShowOverlayMessage(message)
	local scrollFrame = BWQ_QuestScrollFrame;
	local buttons = scrollFrame.buttons;
	message = message or "";
	
	ShowUIPanel(BWQ_WorldQuestFrame.blocker);
	BWQ_WorldQuestFrame.blocker.text:SetText(message);
	BWQ_QuestScrollFrame:EnableMouseWheel(false);
	
	BWQ_WorldQuestFrameFilterButton:Disable();
	BWQ_WorldQuestFrameSortButton:Disable();
	
	for k, button in ipairs(buttons) do
		button:Disable();
	end
end

local function HideOverlayMessage()
	local scrollFrame = BWQ_QuestScrollFrame;
	local buttons = scrollFrame.buttons;
	HideUIPanel(BWQ_WorldQuestFrame.blocker);
	BWQ_QuestScrollFrame:EnableMouseWheel(true);

	BWQ_WorldQuestFrameFilterButton:Enable();
	BWQ_WorldQuestFrameSortButton:Enable();
	
	for k, button in ipairs(buttons) do
		button:Enable();
	end
end

local function ZoneHasSpecificQuests(zoneId)
	for k, v in ipairs(_legionZoneIds) do
		if v == zoneId then return true; end
	end
	return false;
end

local function GetOrCreateQuestInfo()
	for k, info in ipairs(_questPool) do
		if info.id == -1 then
			return info;
		end
	end

	local info = {["id"] = -1, ["title"] = "", ["timeString"] = "", ["timeStringShort"] = "", ["color"] = BWQ_WHITE_FONT_COLOR, ["minutes"] = 0
					, ["faction"] = 0, ["type"] = 0, ["rarity"] = 0, ["isElite"] = false, ["tradeskill"] = 0
					, ["numObjectives"] = 0, ["numItems"] = 0, ["rewardTexture"] = "", ["rewardQuality"] = 1
					, ["rewardType"] = 0};
	table.insert(_questPool, info);
	
	return info
end

local function GetSortedFilterOrder(filterId)
	local filter = BWQ.settings.filters[filterId];
	local tbl = {};
	for k, v in pairs(filter.flags) do
		table.insert(tbl, k);
	end
	table.sort(tbl, function(a, b) 
				return a < b; 
			end)
	return tbl;
end

local function Sort_questList(list)
	table.sort(list, function(a, b) 
			-- if both times are not showing actual minutes, check if they are within 2 minutes, else just check if they are the same
			if (a.minutes > 60 and b.minutes > 60 and math.abs(a.minutes - b.minutes) < 2) or a.minutes == b.minutes then
				return a.title < b.title;
			end	
			return a.minutes < b.minutes;
	end);
end

local function Sort_questListByZone(list)
	table.sort(list, function(a, b) 
		if a.zoneId == b.zoneId then
			-- if both times are not showing actual minutes, check if they are within 2 minutes, else just check if they are the same
			if (a.minutes > 60 and b.minutes > 60 and math.abs(a.minutes - b.minutes) < 2) or a.minutes == b.minutes then
				return a.title < b.title;
			end	
			return a.minutes < b.minutes;
		end
		return a.zoneId < b.zoneId;
	end);
end

local function Sort_questListByFaction(list)
	table.sort(list, function(a, b) 
		if a.faction == b.faction then
			-- if both times are not showing actual minutes, check if they are within 2 minutes, else just check if they are the same
			if (a.minutes > 60 and b.minutes > 60 and math.abs(a.minutes - b.minutes) < 2) or a.minutes == b.minutes then
				return a.title < b.title;
			end	
			return a.minutes < b.minutes;
		end
		return a.faction < b.faction;
	end);
end

local function Sort_questListByType(list)
	table.sort(list, function(a, b) 
		local aIsCriteria = WorldMapFrame.UIElementsFrame.BountyBoard:IsWorldQuestCriteriaForSelectedBounty(a.id);
		local bIsCriteria = WorldMapFrame.UIElementsFrame.BountyBoard:IsWorldQuestCriteriaForSelectedBounty(b.id);
		if aIsCriteria == bIsCriteria then
			if a.type == b.type then
				if a.rarity == b.rarity then
					if (a.isElite and b.isElite) or (not a.isElite and not b.isElite) then
						-- if both times are not showing actual minutes, check if they are within 2 minutes, else just check if they are the same
						if (a.minutes > 60 and b.minutes > 60 and math.abs(a.minutes - b.minutes) < 2) or a.minutes == b.minutes then
							return a.title < b.title;
						end	
						return a.minutes < b.minutes;
					end
					return b.isElite;
				end
				return a.rarity < b.rarity;
			end
			return a.type < b.type;
		end
		return aIsCriteria and not bIsCriteria;
	end);
end

local function Sort_questListByName(list)
	table.sort(list, function(a, b) 
		return a.title < b.title;
	end);
end

local function Sort_questListByReward(list)
	table.sort(list, function(a, b) 
		if a.rewardType == b.rewardType then
			if not a.rewardQuality or not b.rewardQuality or a.rewardQuality == b.rewardQuality then
				if not a.numItems or not b.numItems or a.numItems == b.numItems then
					-- if both times are not showing actual minutes, check if they are within 2 minutes, else just check if they are the same
					if (a.minutes > 60 and b.minutes > 60 and math.abs(a.minutes - b.minutes) < 2) or a.minutes == b.minutes then
						return a.title < b.title;
					end	
					return a.minutes < b.minutes;
				
				end
				return a.numItems > b.numItems;
			end
			return a.rewardQuality > b.rewardQuality;
		elseif a.rewardType == 0 or b.rewardType == 0 then
			return a.rewardType > b.rewardType;
		end
		return a.rewardType < b.rewardType;
	end);
end

local function GetQuestTimeString(questId)
	local timeLeftMinutes = C_TaskQuest.GetQuestTimeLeftMinutes(questId);
	local timeString = "";
	local timeStringShort = "";
	local color = BWQ_WHITE_FONT_COLOR;
	if ( timeLeftMinutes ) then
		if ( timeLeftMinutes <= WORLD_QUESTS_TIME_CRITICAL_MINUTES ) then
			-- Grace period, show the actual time left
			color = RED_FONT_COLOR;
			timeString = SecondsToTime(timeLeftMinutes * 60);
		elseif timeLeftMinutes <= 60 + WORLD_QUESTS_TIME_CRITICAL_MINUTES then
			timeString = SecondsToTime((timeLeftMinutes - WORLD_QUESTS_TIME_CRITICAL_MINUTES) * 60);
			color = BWQ_ORANGE_FONT_COLOR;
		elseif timeLeftMinutes < 24 * 60 + WORLD_QUESTS_TIME_CRITICAL_MINUTES then
			timeString = D_HOURS:format(math.floor(timeLeftMinutes - WORLD_QUESTS_TIME_CRITICAL_MINUTES) / 60);
			color = BWQ_GREEN_FONT_COLOR
		else
			timeString = D_DAYS:format(math.floor(timeLeftMinutes - WORLD_QUESTS_TIME_CRITICAL_MINUTES) / 1440);
			color = BWQ_BLUE_FONT_COLOR;
		end
	end
	-- for some reason using a single match makes t always 4 while the match works fine outside this function
	local t = string.match(timeString, '(%d+)');
	local s = string.match(timeString, '(%a)');
	-- Attempt Russian
	if t and not s then
		s = string.match(timeString, ' (.[\128-\191]*)');
	end
	if t and s then
		timeStringShort = t..s;
	end

	return timeLeftMinutes, timeString, color, timeStringShort;
end

function BWQ:SetQuestReward(info)

	local _, texture, numItems, quality, rewardType = nil, "", 0, 1, 0;
	
	if GetNumQuestLogRewards(info.id) > 0 then
		_, texture, numItems, quality = GetQuestLogRewardInfo(1, info.id);
		local itemId = select(6, GetQuestLogRewardInfo(1, info.id))
		if itemId and IsArtifactItem(itemId) then
			WorldMap_AddQuestRewardsToTooltip(info.id);
			local text = WorldMapTooltipTooltipTextLeft4:GetText();
			text = text:gsub(",", "");
			numItems = tonumber(string.match(text, '%d+'));
			rewardType = BWQ_REWARDTYPE_ARTIFACT;
			WorldMapTooltip:Hide();
		elseif itemId and select(9, GetItemInfo(itemId)) ~= "" then
			rewardType = BWQ_REWARDTYPE_ARMOR;
		else
			rewardType = BWQ_REWARDTYPE_ITEM;
		end
	elseif GetNumQuestLogRewardCurrencies(info.id) > 0 then
		_, texture, numItems = GetQuestLogRewardCurrencyInfo(1, info.id)
		rewardType = BWQ_REWARDTYPE_CURRENCY;
	-- Check gold last because of <2g rewards
	elseif GetQuestLogRewardMoney(info.id) > 0 then
		numItems = floor(abs(GetQuestLogRewardMoney(info.id) / 10000))
		texture = "Interface/ICONS/INV_Misc_Coin_01";
		rewardType = BWQ_REWARDTYPE_GOLD;
	
	end
	info.rewardQuality = quality or 1;
	info.rewardTexture = texture ~= "" and texture or BWQ_QUESTIONMARK;
	info.numItems = numItems or 0;
	info.rewardType = rewardType or 0;
end

local function AddQuestToList(list, qInfo, zoneId)
	local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex = GetQuestTagInfo(qInfo.questId);
	local title, factionId = C_TaskQuest.GetQuestInfoByQuestID(qInfo.questId);
	local minutes, timeString, color, timeStringShort = GetQuestTimeString(qInfo.questId);
	if minutes == 0 then return end;
	local faction = factionId and GetFactionInfoByID(factionId) or "";
	
	local info = GetOrCreateQuestInfo();
	info.id = qInfo.questId;
	info.title = title;
	info.timeString = timeString;
	info.timeStringShort = timeStringShort;
	info.color = color;
	info.minutes = minutes;
	info.faction = faction;
	info.factionId = factionId;
	info.type = worldQuestType;
	info.rarity = rarity;
	info.isElite = isElite;
	info.zoneId = zoneId;
	info.tradeskill = tradeskillLineIndex;
	info.numObjectives = qInfo.numObjectives;
	info.passedFilter = true;
	BWQ:SetQuestReward(info)
	table.insert(list, info)
	
	return info;
end

local function DisplayQuestType(frame, questInfo)
	local inProgress = false;
	local isCriteria = WorldMapFrame.UIElementsFrame.BountyBoard:IsWorldQuestCriteriaForSelectedBounty(questInfo.id);
	local questType, rarity, isElite, tradeskillLineIndex = questInfo.type, questInfo.rarity, questInfo.isElite, questInfo.tradeskill
	
	frame:Show();
	frame:SetWidth(frame:GetHeight());
	frame.texture:Show();
	
	if isElite then
		frame.elite:Show();
	else
		frame.elite:Hide();
	end
	
	if rarity == LE_WORLD_QUEST_QUALITY_COMMON then
		frame.bg:SetTexture("Interface/WorldMap/UI-QuestPoi-NumberIcons");
		frame.bg:SetTexCoord(0.875, 1, 0.375, 0.5);
		frame.bg:SetSize(28, 28);
	elseif rarity == LE_WORLD_QUEST_QUALITY_RARE then
		frame.bg:SetAtlas("worldquest-questmarker-rare");
		frame.bg:SetTexCoord(0, 1, 0, 1);
		frame.bg:SetSize(18, 18);
	elseif rarity == LE_WORLD_QUEST_QUALITY_EPIC then
		frame.bg:SetAtlas("worldquest-questmarker-epic");
		frame.bg:SetTexCoord(0, 1, 0, 1);
		frame.bg:SetSize(18, 18);
	end
	
	local tradeskillLineID = tradeskillLineIndex and select(7, GetProfessionInfo(tradeskillLineIndex));
	if ( questType == LE_QUEST_TAG_TYPE_PVP ) then
		if ( inProgress ) then
			frame.texture:SetAtlas("worldquest-questmarker-questionmark");
			frame.texture:SetSize(10, 15);
		else
			frame.texture:SetAtlas("worldquest-icon-pvp-ffa", true);
		end
	elseif ( questType == LE_QUEST_TAG_TYPE_PET_BATTLE ) then
		if ( inProgress ) then
			frame.texture:SetAtlas("worldquest-questmarker-questionmark");
			frame.texture:SetSize(10, 15);
		else
			frame.texture:SetAtlas("worldquest-icon-petbattle", true);
		end
	elseif ( questType == LE_QUEST_TAG_TYPE_PROFESSION and WORLD_QUEST_ICONS_BY_PROFESSION[tradeskillLineID] ) then
		if ( inProgress ) then
			frame.texture:SetAtlas("worldquest-questmarker-questionmark");
			frame.texture:SetSize(10, 15);
		else
			frame.texture:SetAtlas(WORLD_QUEST_ICONS_BY_PROFESSION[tradeskillLineID], true);
		end
	elseif ( questType == LE_QUEST_TAG_TYPE_DUNGEON ) then
		if ( inProgress ) then
			frame.texture:SetAtlas("worldquest-questmarker-questionmark");
			frame.texture:SetSize(10, 15);
		else
			frame.texture:SetAtlas("worldquest-icon-dungeon", true);
		end
	else
		if ( inProgress ) then
			frame.texture:SetAtlas("worldquest-questmarker-questionmark");
			frame.texture:SetSize(10, 15);
		else
			frame.texture:SetAtlas("worldquest-questmarker-questbang");
			frame.texture:SetSize(6, 15);
		end
	end
	
	if ( isCriteria ) then
		if ( isElite ) then
			frame.criteriaGlow:SetAtlas("worldquest-questmarker-dragon-glow", false);
			frame.criteriaGlow:SetPoint("CENTER", 0, -1);
		else
			frame.criteriaGlow:SetAtlas("worldquest-questmarker-glow", false);
			frame.criteriaGlow:SetPoint("CENTER", 0, 0);
		end
		frame.criteriaGlow:Show();
	else
		frame.criteriaGlow:Hide();
	end
end

function BWQ:IsFiltering()

	for k, category in pairs(BWQ.settings.filters)do
		for k2, flag in pairs(category.flags) do
			if flag then return true; end
		end
	end
	return false;
end

function BWQ:isUsingFilterNr(id)

	if not BWQ.settings.filters[id] then return false end
	local flags = BWQ.settings.filters[id].flags;
	for k, flag in pairs(flags) do
		if flag then return true; end
	end
	return false;
end

function BWQ:PassesAllFilters(quest)


	-- local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex = GetQuestTagInfo(qInfo.questId);
	-- local title, factionId = C_TaskQuest.GetQuestInfoByQuestID(qInfo.questId);
	-- local faction = factionId and GetFactionInfoByID(factionId) or "";
	
	-- if BWQ:isUsingFilterNr(1) and not BWQ:PassesFactionFilter(faction ,factionId) then return false; end
	-- if BWQ:isUsingFilterNr(2) and not BWQ:PassesTypeFilter(worldQuestType, isElite, qInfo.questId) then return false; end
	-- if BWQ:isUsingFilterNr(3) and not BWQ:PassesRewardFilter(qInfo.questId, q.rewardType) then return false; end
	
	-- local tagID, tagName, worldQuestType, rarity, isElite, tradeskillLineIndex = GetQuestTagInfo(quest.id);
	-- local title, factionId = C_TaskQuest.GetQuestInfoByQuestID(quest.id);
	-- local faction = factionId and GetFactionInfoByID(factionId) or "";
	
	if BWQ:isUsingFilterNr(1) and not BWQ:PassesFactionFilter(quest) then return false; end
	if BWQ:isUsingFilterNr(2) and not BWQ:PassesTypeFilter(quest.type, quest.isElite, quest.id) then return false; end
	if BWQ:isUsingFilterNr(3) and not BWQ:PassesRewardFilter(quest.id, quest.rewardType) then return false; end
	
	return true;
end

function BWQ:PassesFactionFilter(quest)

	--local faction = factionId and GetFactionInfoByID(factionId) or "";
	-- Factions (1)
	local flags = BWQ.settings.filters[1].flags
	if flags[quest.faction] ~= nil and flags[quest.faction] then return true; end
	return false;
end

function BWQ:PassesTypeFilter(worldQuestType, isElite, questId)

	-- Factions (1)
	flags = BWQ.settings.filters[2].flags
	-- Default
	if flags["Default"] and worldQuestType ~= LE_QUEST_TAG_TYPE_PVP and worldQuestType ~= LE_QUEST_TAG_TYPE_PET_BATTLE and worldQuestType ~= LE_QUEST_TAG_TYPE_DUNGEON and  worldQuestType ~= LE_QUEST_TAG_TYPE_PROFESSION then
		return true;
	end
	-- Elite
	if flags["Elite"] and isElite then return true; end
	-- PvP
	if flags["PvP"] and worldQuestType == LE_QUEST_TAG_TYPE_PVP then return true; end
	-- Petbattle
	if flags["Petbattle"] and worldQuestType == LE_QUEST_TAG_TYPE_PET_BATTLE then return true; end
	-- Dungeon
	if flags["Dungeon"] and worldQuestType == LE_QUEST_TAG_TYPE_DUNGEON then return true; end
	-- Profession
	if flags["Profession"] and worldQuestType == LE_QUEST_TAG_TYPE_PROFESSION then return true; end
	-- Emissary
	if flags["Emissary"] and WorldMapFrame.UIElementsFrame.BountyBoard:IsWorldQuestCriteriaForSelectedBounty(questId) then return true; end
	;
	return false;
end

function BWQ:PassesRewardFilter(questId, rewardType)

	if(rewardType == 0) then return false end;
	local flags = BWQ.settings.filters[3].flags
	-- Armor
	if id and flags["Armor"] and rewardType == BWQ_REWARDTYPE_ARMOR then
		return true;
	end
	-- Item
	if id and flags["Item"] and rewardType == BWQ_REWARDTYPE_ITEM then
		return true;
	end
	-- Artifact power
	if id and flags["Artifact"] and rewardType == BWQ_REWARDTYPE_ARTIFACT then
		return true;
	end
	-- Gold
	if  flags["Gold"] and rewardType == BWQ_REWARDTYPE_GOLD then return true; end
	-- Resources
	if  flags["Resources"] and rewardType == BWQ_REWARDTYPE_CURRENCY then return true; end

	--[[
	local flags = BWQ.settings.filters[3].flags
	-- Item
	if (flags["Armor"] or flags["Artifact"] or flags["Item"]) and GetNumQuestLogRewards(questId) > 0 then
		
		local id = select(6, GetQuestLogRewardInfo(1, questId))
		if not id then return false end
		local link = select(2, GetItemInfo(id));
		-- Armor
		if id and flags["Armor"] and select(9, GetItemInfo(id)) ~= "" then
			return true;
		end
		-- Item
		if id and flags["Item"] and select(9, GetItemInfo(id)) == "" and not IsArtifactItem(id) then
			return true;
		end
		-- Artifact power
		if id and flags["Artifact"] and IsArtifactItem(id) then
			return true;
		end
	end
	-- Gold, check item rewards because some have 2g rewards we don't care about
	if  flags["Gold"] and GetQuestLogRewardMoney(questId) > 0 and GetNumQuestLogRewards(questId) == 0 then return true; end
	-- Resources
	if  flags["Resources"] and GetNumQuestLogRewardCurrencies(questId) > 0 then return true; end
	]]--
end

function BWQ:UpdateFilterDisplay()

	local filterList = "";
	
	for kO, option in pairs(BWQ.settings.filters) do
		for kF, flag in pairs(option.flags) do
			if flag then
				filterList = filterList == "" and kF or string.format("%s, %s", filterList, kF);
			end
		end
	end

	BWQ_WorldQuestFrame.filterBar.text:SetText(BWQ_FILTERS:format(filterList)); 
	BWQ_WorldQuestFrame.filterBar:SetHeight(20);
end

function BWQ:FilterMapPoI()

	if InCombatLockdown() or not ZoneHasSpecificQuests(GetCurrentMapAreaID()) then return; end
	
	local index = 1;
	local PoI = _G["WorldMapFrameTaskPOI"..index];
	local quest = nil;

	while(PoI) do
		if (PoI.worldQuest) then
			quest = GetQuestFromList(PoI.questID);
			if (quest) then
				if (BWQ.settings.filterPoI and not quest.passedFilter) then
					PoI:Hide();
				else
					PoI:Show();
				end
				
				if (not PoI.BWQRing) then
					PoI.BWQRing = PoI:CreateTexture(nil)
					PoI.BWQRing:SetWidth(22);
					PoI.BWQRing:SetHeight(22);
					PoI.BWQRing:SetDrawLayer("OVERLAY", 4)
					PoI.BWQRing:SetPoint("CENTER", PoI, "CENTER", 0, -1)
					PoI.BWQRing:SetTexture("Interface/PLAYERFRAME/UI-PlayerFrame-Deathknight-Ring")
					PoI.BWQRing:SetTexCoord(0, 1, 0, 1)
					PoI.BWQRing:SetVertexColor(0.85, 0.65, 0.13) 
					
					PoI.BWQRing2 = PoI:CreateTexture(nil)
					PoI.BWQRing2:SetWidth(21);
					PoI.BWQRing2:SetHeight(21);
					PoI.BWQRing2:SetAlpha(0.5);
					PoI.BWQRing2:SetDrawLayer("OVERLAY", 5)
					PoI.BWQRing2:SetPoint("CENTER", PoI, "CENTER", 0, 0)
					PoI.BWQRing2:SetTexture("Interface/Artifacts/Artifacts")
					PoI.BWQRing2:SetTexCoord(0.873046875, 0.939453125, 0.4580078125, 0.525390625)
					PoI.BWQRing2:SetBlendMode("ADD")
					PoI.BWQRing2:SetVertexColor(0, 0.5, 0) 
				end
				
				if (not PoI.BWQText) then
					PoI.BWQText = PoI:CreateFontString(nil, nil, "BWQ_NumberFontOutline")
					PoI.BWQText:SetPoint("TOP", PoI, "BOTTOM", 1, 3)
					PoI.BWQText:SetHeight(18);
					PoI.BWQText:SetWidth(30);
					PoI.BWQText:SetDrawLayer("OVERLAY", 7)
					PoI.BWQText:SetJustifyV("MIDDLE")
					
					PoI.BWQBG = PoI:CreateTexture("")
					PoI.BWQBG:SetWidth(22);
					PoI.BWQBG:SetAlpha(0.75);
					PoI.BWQBG:SetDrawLayer("ARTWORK", 3)
					PoI.BWQBG:SetPoint("TOP", PoI, "CENTER", 0, 0)
					PoI.BWQBG:SetHeight(20);
					--PoI.BWQBG:SetPoint("BOTTOM", PoI.BWQText, "BOTTOM", 0, 4)
					PoI.BWQBG:SetTexture("Interface/COMMON/NameShadow")
					PoI.BWQBG:SetTexCoord(0.05, 0.95, 0.8, 0)
				end
			
				if (PoI.BWQRing) then
					PoI.BWQRing:SetAlpha(BWQ.settings.showPinReward and 1 or 0);
					PoI.BWQRing2:SetAlpha(BWQ.settings.showPinReward and 1 or 0);
					if (BWQ.settings.showPinReward) then
						PoI.Texture:SetWidth(18);
						PoI.Texture:SetHeight(18);
						SetPortraitToTexture(PoI.Texture, quest.rewardTexture)
						PoI:SetNormalTexture(nil);
						PoI:SetPushedTexture(nil);
						--PoI:SetHighlightTexture(nil);
						PoI.BWQRing:Show();
						
						-- Give AP items a green ring
						if (quest.rewardType == BWQ_REWARDTYPE_ARTIFACT) then
							PoI.BWQRing2:Show()
						else
							PoI.BWQRing2:Hide()
						end
						
						-- Darken ring for emmisary to better display their glow
						if (_G["WorldMapFrameTaskPOI"..index.."CriteriaMatchGlow"]:IsShown()) then
							PoI.BWQRing:SetVertexColor(0.65, 0.50, 0.05) 
						else
							PoI.BWQRing:SetVertexColor(0.85, 0.65, 0.13) 
						end
					end
				end
				
				if (PoI.BWQText) then
					PoI.BWQText:SetAlpha((BWQ.settings.showPinTime and quest.timeStringShort ~= "")and 1 or 0);
					PoI.BWQBG:SetAlpha((BWQ.settings.showPinTime and quest.timeStringShort ~= "") and 0.75 or 0);
					if(BWQ.settings.showPinTime) then
						PoI.BWQText:SetText(quest.timeStringShort)
						PoI.BWQText:SetVertexColor(quest.color.r, quest.color.g, quest.color.b) 
					end
				end
			end
		end
		index = index + 1;
		PoI = _G["WorldMapFrameTaskPOI"..index];
	end
end

function BWQ:ApplySort()

	local list = _questList;
	local sortOption = Lib_UIDropDownMenu_GetSelectedValue(BWQ_WorldQuestFrameSortButton);
	if sortOption == 2 then -- faction
		Sort_questListByFaction(list);
	elseif sortOption == 3 then -- type
		Sort_questListByType(list);
	elseif sortOption == 4 then -- zone
		Sort_questListByZone(list);
	elseif sortOption == 5 then -- name
		Sort_questListByName(list);
	elseif sortOption == 6 then -- reward
		Sort_questListByReward(list)
	else -- time or anything else
		Sort_questList(list)
	end
end

function BWQ:UpdateQuestList(skipPins)

	if (InCombatLockdown() or not WorldMapFrame:IsShown()) then return end
	
	if UnitLevel("player") < 110 then
		ShowOverlayMessage(BWQ_UNLOCK_110);
		return;
	end
	
	if not _completedQuest then
		ShowOverlayMessage(string.format(BWQ_UNLOCK_QUEST, _questTitle));
		return;
	end
	
	local list = _questList;
	local mapAreaID = GetCurrentMapAreaID();
	local isQuestZone = ZoneHasSpecificQuests(mapAreaID);
	local filteredOut = 0;
	local isFiltering = BWQ:IsFiltering()
	local quest = nil;
	local questsById = nil
	
	for i=#list, 1, -1 do
		list[i].id = -1;
		table.remove(list, i);
	end
	
	if isQuestZone then
		questsById = C_TaskQuest.GetQuestsForPlayerByMapID(mapAreaID);
		if questsById and type(questsById) == "table" then
			for k, info in ipairs(questsById) do
				--if not isFiltering or BWQ:PassesAllFilters(info) then
					quest = AddQuestToList(list, info, mapAreaID);
					if quest and isFiltering and not BWQ:PassesAllFilters(quest) then
						quest.passedFilter = false;
					end
				--end
			end
		end
	else
		for k, zoneId in ipairs(_legionZoneIds) do
			questsById = C_TaskQuest.GetQuestsForPlayerByMapID(zoneId);
			if questsById and type(questsById) == "table" then
				for k2, info in ipairs(questsById) do
					--if not isFiltering or BWQ:PassesAllFilters(info) then
						quest = AddQuestToList(list, info, zoneId);
						if quest and isFiltering and not BWQ:PassesAllFilters(quest) then
							quest.passedFilter = false;
						end
					--end
				end
			end
		end
		if #list == 0 then
			ShowOverlayMessage(BWQ_NOT_HERE);
		end
	end

	BWQ:ApplySort()
	
	self.time = 0;
	BWQ:DisplayQuestList();
	if(not skipPins) then
		BWQ:FilterMapPoI();
	end
	
	if isFiltering then
		BWQ:UpdateFilterDisplay()
	else
		BWQ_WorldQuestFrame.filterBar.text:SetText(""); 
		BWQ_WorldQuestFrame.filterBar:SetHeight(0.1);
	end
	BWQ_WorldQuestFrame.filterBar.clearButton:SetShown(isFiltering);
end

local function PopulateDisplayList()
	for i=#_questDisplayList, 1, -1 do
		table.remove(_questDisplayList, i);
	end

	local isFiltering = BWQ:IsFiltering();
	
	for k, quest in ipairs(_questList) do
		if isFiltering then
			quest.passedFilter = BWQ:PassesAllFilters(quest)
			if quest.passedFilter then
				table.insert(_questDisplayList, quest);
			end
		elseif not isFiltering then
			table.insert(_questDisplayList, quest);
		end
	end
end

function BWQ:UpdateMissingRewards()

	if #_questsMissingReward == 0 then return; end

	local q;
	for i = #_questsMissingReward, 1, -1 do
		q = _questsMissingReward[i]
		if q.rewardTexture == BWQ_QUESTIONMARK then
			BWQ:SetQuestReward(q)
		end
		table.remove(_questsMissingReward, i);
	end
	
	BWQ:ApplySort();
end

function BWQ:DisplayQuestList()

	if InCombatLockdown() or UnitLevel("player") < 110 or not WorldMapFrame:IsShown() or not BWQ_WorldQuestFrame:IsShown() then return end
	local scrollFrame = BWQ_QuestScrollFrame;
	local offset = HybridScrollFrame_GetOffset(scrollFrame);
	local buttons = scrollFrame.buttons;
	if buttons == nil then return; end
	
	BWQ:UpdateMissingRewards();
	PopulateDisplayList()
	local list = _questDisplayList;
	local mapAreaID = GetCurrentMapAreaID();
	local isQuestZone = ZoneHasSpecificQuests(mapAreaID);
	local rewardMissing = false;
	local r, g, b = 1, 1, 1;
	local filteredSkipped = 0;
	
	-- In case an error happens during the update, pevent OnUpdate
	-- Big issue if it happens when fast updating
	addon.events.noIssue = false;
	HideOverlayMessage();
	
	
	
	for i=1, #buttons do
		local button = buttons[i];
		local displayIndex = i + offset + filteredSkipped;
		button:Hide();
		button.reward.amount:Hide();
		button.trackedBorder:Hide();
		button.info = nil;
		if ( displayIndex <= #list) then
			local q = list[displayIndex];
			button:Show();
			button.title:SetText(q.title);
			button.time:SetTextColor(q.color.r, q.color.g, q.color.b, 1);
			button.time:SetText(q.timeString);
			--button.time:SetText("          -");
			button.extra:SetText(isQuestZone and "" or GetMapNameByID(q.zoneId));
			
			button.title:ClearAllPoints()
			button.title:SetPoint("RIGHT", button.reward, "LEFT", -5, 0);
			if BWQ.settings.showFactionIcon then
				button.title:SetPoint("BOTTOMLEFT", button.faction, "RIGHT", 5, 1);
			elseif BWQ.settings.showTypeIcon then
				button.title:SetPoint("BOTTOMLEFT", button.type, "RIGHT", 5, 1);
			else
				button.title:SetPoint("BOTTOMLEFT", button, "LEFT", 10, 0);
			end
			
			if BWQ.settings.showFactionIcon then
				button.faction:Show();
				button.faction.icon:SetTexture(_factionIcons[q.factionId] or "");
				button.faction:SetWidth(button.faction:GetHeight());
			else
				button.faction:Hide();
				button.faction:SetWidth(0.1);
			end
			
			if BWQ.settings.showTypeIcon then
				
				DisplayQuestType(button.type, q)
			else
				button.type:Hide()
				button.type:SetWidth(0.1);
			end
			
			-- display reward
			button.reward:Show();
			button.reward.icon:Show();
			r, g, b = GetItemQualityColor(q.rewardQuality);
			button.reward.iconBorder:SetVertexColor(r, g, b);
			button.reward.icon:SetTexture(q.rewardTexture);

			if q.numItems and q.numItems > 1 then
				button.reward.amount:SetText(GetAbreviatedNumber(q.numItems) );
				button.reward.amount:Show();
				if q.rewardType == BWQ_REWARDTYPE_ARTIFACT then
					r, g, b = GetItemQualityColor(2);
				else
					r, g, b = 1, 1, 1;
				end
				button.reward.amount:SetVertexColor(r, g, b);
			end
			
			if GetSuperTrackedQuestID() == q.id or IsWorldQuestWatched(q.id) then
				button.trackedBorder:Show();
			end
			
			button.info = q;
			button.zoneId = q.zoneId;
			button.questId = q.id;
			button.numObjectives = q.numObjectives;
		end
	end
	
	for k, quest in ipairs(_questList) do
		if quest.rewardType == 0 then
			rewardMissing = true;
			table.insert(_questsMissingReward, quest)
		end
	end
	
	HybridScrollFrame_Update(BWQ_QuestScrollFrame, #list * BWQ_LISTITTEM_HEIGHT, scrollFrame:GetHeight());
	
	addon.events.noIssue = true;
	addon.events.updatePeriod = rewardMissing and BWQ_REFRESH_FAST or BWQ_REFRESH_DEFAULT;
	
	BWQ:FilterMapPoI()
	
	--BWQ_Tab_Onclick(BWQ_WorldQuestFrame.selectedTab)
end

function BWQ:SetAllFilterTo(id, value)

	local options = BWQ.settings.filters[id].flags;
	for k, v in pairs(options) do
		options[k] = value;
	end
end

function BWQ:InitFilter(self, level)

	local info = Lib_UIDropDownMenu_CreateInfo();
	info.keepShownOnClick = true;	
	
	if level == 1 then
		info.checked = 	nil;
		info.isNotRadio = nil;
		info.func =  nil;
		info.hasArrow = true;
		info.notCheckable = true;
		
		for k, v in pairs(BWQ.settings.filters) do
			info.text = v.name;
			info.value = k;
			Lib_UIDropDownMenu_AddButton(info, level)
		end
		
		info.text = "Settings";
		info.value = 0;
		Lib_UIDropDownMenu_AddButton(info, level)
	else --if level == 2 then
		info.hasArrow = false;
		info.isNotRadio = true;
		if LIB_UIDROPDOWNMENU_MENU_VALUE then
			if BWQ.settings.filters[LIB_UIDROPDOWNMENU_MENU_VALUE] then
				
				info.notCheckable = true;
					
				info.text = CHECK_ALL
				info.func = function()
								BWQ:SetAllFilterTo(LIB_UIDROPDOWNMENU_MENU_VALUE, true);
								Lib_UIDropDownMenu_Refresh(self, 1, 2);
								BWQ:UpdateQuestList();
							end
				Lib_UIDropDownMenu_AddButton(info, level)
				
				info.text = UNCHECK_ALL
				info.func = function()
								BWQ:SetAllFilterTo(LIB_UIDROPDOWNMENU_MENU_VALUE, false);
								Lib_UIDropDownMenu_Refresh(self, 1, 2);
								BWQ:UpdateQuestList();
							end
				Lib_UIDropDownMenu_AddButton(info, level)
			
				info.notCheckable = false;
				local options = BWQ.settings.filters[LIB_UIDROPDOWNMENU_MENU_VALUE].flags;
				local order = _filterOrders[LIB_UIDROPDOWNMENU_MENU_VALUE] 
				
				for k, flagKey in pairs(order) do
				
					info.text = flagKey;
					info.func = function(_, _, _, value)
										options[flagKey] = value;
										BWQ:UpdateQuestList();
									end
					info.checked = function() return options[flagKey] end;
					Lib_UIDropDownMenu_AddButton(info, level);			
				end
				
			end
			if LIB_UIDROPDOWNMENU_MENU_VALUE == 0 then
				info.notCheckable = false;
				info.text = "Default Tab";
				info.func = function(_, _, _, value)
						BWQ.settings.defaultTab = value;
						--BWQ:UpdateQuestList();
					end
				info.checked = function() return BWQ.settings.defaultTab end;
				Lib_UIDropDownMenu_AddButton(info, level);			
				
				info.text = "Save Filters";
				info.func = function(_, _, _, value)
						BWQ.settings.saveFilters = value;
					end
				info.checked = function() return BWQ.settings.saveFilters end;
				Lib_UIDropDownMenu_AddButton(info, level);	
				
				info.text = "Filter map pins";
				info.func = function(_, _, _, value)
						BWQ.settings.filterPoI = value;
						WorldMap_UpdateQuestBonusObjectives();
					end
				info.checked = function() return BWQ.settings.filterPoI end;
				Lib_UIDropDownMenu_AddButton(info, level);
				
				-- info.text = "Default map pins";
				-- info.func = function(_, _, _, value)
						-- BWQ.settings.defaultPoI = value;
						-- WorldMap_UpdateQuestBonusObjectives();
					-- end
				-- info.checked = function() return BWQ.settings.defaultPoI end;
				-- Lib_UIDropDownMenu_AddButton(info, level);
				
				info.text = "Map pin rewards";
				info.func = function(_, _, _, value)
						BWQ.settings.showPinReward = value;
						WorldMap_UpdateQuestBonusObjectives();
					end
				info.checked = function() return BWQ.settings.showPinReward end;
				Lib_UIDropDownMenu_AddButton(info, level);
				
				info.text = "Map pin time";
				info.func = function(_, _, _, value)
						BWQ.settings.showPinTime = value;
						WorldMap_UpdateQuestBonusObjectives();
					end
				info.checked = function() return BWQ.settings.showPinTime end;
				Lib_UIDropDownMenu_AddButton(info, level);
				
				info.text = "Show Type";
				info.func = function(_, _, _, value)
						BWQ.settings.showTypeIcon = value;
						BWQ:UpdateQuestList();
					end
				info.checked = function() return BWQ.settings.showTypeIcon end;
				Lib_UIDropDownMenu_AddButton(info, level);		
				
				info.text = "Show Faction";
				info.func = function(_, _, _, value)
						BWQ.settings.showFactionIcon = value;
						BWQ:UpdateQuestList();
					end
				info.checked = function() return BWQ.settings.showFactionIcon end;
				Lib_UIDropDownMenu_AddButton(info, level);		
			end
		end
	end

end

function BWQ:InitSort(self, level)

	local selectedValue = Lib_UIDropDownMenu_GetSelectedValue(self);
	local info = Lib_UIDropDownMenu_CreateInfo();
	local buttonsAdded = 0;
	info.func = function(self, category) BWQ:Sort_OnClick(self, category) end
	
	for k, option in ipairs(_sortOptions) do
		info.text = option;
		info.arg1 = k;
		info.value = k;
		if k == selectedValue then
			info.checked = 1;
		else
			info.checked = nil;
		end
		Lib_UIDropDownMenu_AddButton(info, level);
		buttonsAdded = buttonsAdded + 1;
	end
	
	return buttonsAdded;
end

function BWQ:Sort_OnClick(self, category)

	
	local dropdown = BWQ_WorldQuestFrameSortButton;
	if ( category and dropdown.active ~= category ) then
		Lib_CloseDropDownMenus();
		dropdown.active = category
		Lib_UIDropDownMenu_SetSelectedValue(dropdown, category);
		Lib_UIDropDownMenu_SetText(dropdown, BWQ_SORT_BY:format(_sortOptions[category]));
		BWQ.settings.sortBy = category;
		BWQ:UpdateQuestList();
	end
end

function BWQ:InitTrackDropDown(self, level)

	if not self:GetParent() or not self:GetParent().info then return; end
	local questId = self:GetParent().info.id;
	local isTracked = (IsWorldQuestHardWatched(questId) or (IsWorldQuestWatched(questId) and GetSuperTrackedQuestID() == questId))
	local info = Lib_UIDropDownMenu_CreateInfo();
	info.notCheckable = true;	

	if isTracked then
		info.text = UNTRACK_QUEST;
		info.func = function(_, _, _, value)
					BonusObjectiveTracker_UntrackWorldQuest(questId)
					BWQ:DisplayQuestList();
				end
	else
		info.text = TRACK_QUEST;
		info.func = function(_, _, _, value)
					BonusObjectiveTracker_TrackWorldQuest(questId, true);
					BWQ:DisplayQuestList();
				end
	end	
	Lib_UIDropDownMenu_AddButton(info, level)
	
	info.text = CANCEL;
	info.func = nil;
	Lib_UIDropDownMenu_AddButton(info, level)
end

function BWQ:OnInitialize()

	self.db = LibStub("AceDB-3.0"):New("BWQDB", _defaults, true);
	self.settings = self.db.global;
end

function BWQ:OnEnable()

	BWQ_TabNormal.Highlight:Show();
	BWQ_TabNormal.TabBg:SetTexCoord(0.01562500, 0.79687500, 0.78906250, 0.95703125);
	BWQ_TabWorld.TabBg:SetTexCoord(0.01562500, 0.79687500, 0.61328125, 0.78125000);
	
	BWQ_QuestScrollFrame.scrollBar.doNotHide = true;
	HybridScrollFrame_CreateButtons(BWQ_QuestScrollFrame, "BWQ_QuestTemplate", 1, 0);
	HybridScrollFrame_Update(BWQ_QuestScrollFrame, 200, BWQ_QuestScrollFrame:GetHeight());
		
	BWQ_QuestScrollFrame.update = function() BWQ:DisplayQuestList() end;

	BWQ_WorldQuestFrameFilterDropDown.noResize = true;
	Lib_UIDropDownMenu_Initialize(BWQ_WorldQuestFrameFilterDropDown, function(self, level) BWQ:InitFilter(self, level) end, "MENU");
	
	if not self.settings.saveFilters then
		for k, filter in pairs(self.settings.filters) do
			BWQ:SetAllFilterTo(k, false);
		end
	end
	
	Lib_UIDropDownMenu_Initialize(BWQ_WorldQuestFrameSortButton, function(self) BWQ:InitSort(self, level) end);
	Lib_UIDropDownMenu_SetWidth(BWQ_WorldQuestFrameSortButton, 90);
	
	if self.settings.saveFilters and _sortOptions[self.settings.sortBy] then
		Lib_UIDropDownMenu_SetSelectedValue(BWQ_WorldQuestFrameSortButton, self.settings.sortBy);
		Lib_UIDropDownMenu_SetText(BWQ_WorldQuestFrameSortButton, BWQ_SORT_BY:format(_sortOptions[self.settings.sortBy]));
	else
		Lib_UIDropDownMenu_SetSelectedValue(BWQ_WorldQuestFrameSortButton, 1);
		Lib_UIDropDownMenu_SetText(BWQ_WorldQuestFrameSortButton, BWQ_SORT_BY:format(_sortOptions[1]));
	end
	
	Lib_UIDropDownMenu_Initialize(BWQ_TrackDropDown, function(self, level) BWQ:InitTrackDropDown(self, level) end, "MENU");

	for k, v in pairs(BWQ.settings.filters) do
		_filterOrders[k] = GetSortedFilterOrder(k);
	end
	
	-- Hooks
	-- Update emissary glow in list
	hooksecurefunc(WorldMapFrame.UIElementsFrame.BountyBoard, "SetSelectedBountyIndex", function() BWQ:DisplayQuestList(); end)
	-- Update update select borders
	hooksecurefunc("TaskPOI_OnClick", function() BWQ:DisplayQuestList() end)
	-- Redo PoI filter when they update
	hooksecurefunc("WorldMap_UpdateQuestBonusObjectives", function()
			BWQ:FilterMapPoI()
			--print("update")
		end)
	-- Hide things when looking at quest details
	hooksecurefunc("QuestMapFrame_ShowQuestDetails", function()
			BWQ_Tab_Onclick(BWQ_TabDetails);
		end)
	-- Show quest tab when leaving quest details
	hooksecurefunc("QuestMapFrame_ReturnFromQuestDetails", function()
			BWQ_Tab_Onclick(BWQ_TabNormal);
		end)
		
	QuestScrollFrame:SetScript("OnShow", function() BWQ_Tab_Onclick(BWQ_TabNormal); end)
	
	
	QuestScrollFrame:SetScript("OnShow", function() 
			if(BWQ_WorldQuestFrame.selectedTab:GetID() == 2) then
				BWQ_Tab_Onclick(BWQ_TabWorld); 
			else
				BWQ_Tab_Onclick(BWQ_TabNormal); 
			end
		end)
		
	-- Scripts
	BWQ_WorldQuestFrame:SetScript("OnShow", function() 
				BWQ:UpdateQuestList();
			end);
	BWQ_TabNormal:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT");
				GameTooltip:SetText("Questlog", nil, nil, nil, nil, true);
				GameTooltip:Show();
			end);
	BWQ_TabWorld:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT");
				GameTooltip:SetText("World Quests", nil, nil, nil, nil, true);
				GameTooltip:Show();
			end);
	BWQ_WorldQuestFrame.filterBar.clearButton:SetScript("OnClick", function (self)
				Lib_CloseDropDownMenus();
				for k, v in pairs(BWQ.settings.filters) do
					BWQ:SetAllFilterTo(k, false);
				end
				self:Hide();
				BWQ:UpdateQuestList();
			end)
	
	local locale = GetLocale();
	if locale == "deDE" then
		_questTitle = "Vereinigung der Inseln";
	elseif locale == "esES" or locale == "esMX" then
		_questTitle = "Unir las Islas";
	elseif locale == "frFR" then
		_questTitle = "L’union des îles";
	elseif locale == "ptBR" then
		_questTitle = "A união das ilhas";
	elseif locale == "itIT" then
		_questTitle = "Unire le Isole";
	end
	
	_completedQuest = GetQuestsCompleted()[43341];
	
	BWQ_Tab_Onclick(self.settings.defaultTab and BWQ_TabWorld or BWQ_TabNormal)
end

local missing = 0;
		
addon.events = CreateFrame("FRAME", "BWQ_EventFrame"); 
addon.events:RegisterEvent("WORLD_MAP_UPDATE");
addon.events:RegisterEvent("PLAYER_REGEN_DISABLED");
addon.events:RegisterEvent("PLAYER_REGEN_ENABLED");
addon.events:RegisterEvent("QUEST_TURNED_IN");
addon.events:RegisterEvent("ADDON_LOADED");
addon.events:RegisterEvent("QUEST_WATCH_LIST_CHANGED");
addon.events:SetScript("OnEvent", function(self, event, ...) if self[event] then self[event](self, ...) else print("BWQ missing function for: " .. event) end end)
addon.events.updatePeriod = BWQ_REFRESH_DEFAULT;
addon.events.time = 0;
addon.events:SetScript("OnUpdate", function(self, elapsed) 
		self.time = self.time + elapsed;
		if addon.events.updatePeriod == BWQ_REFRESH_FAST and self.time >= self.updatePeriod then 
			self.time = 0;
			BWQ:DisplayQuestList()
			missing = missing + 1
			if missing >= BWQ_REFRESH_LIMIT then
				--print(BWQ_REFRESH_FAIL)
				addon.events.updatePeriod = BWQ_REFRESH_DEFAULT
				missing = 0;
			end
		end
		
		if addon.events.noIssue and addon.events.updatePeriod == BWQ_REFRESH_FDEFAULT and self.time >= self.updatePeriod then
			BWQ:UpdateQuestList();
			self.time = 0;
			missing = 0;
		end
	end)

function addon.events:ADDON_LOADED(loaded_addon)
	if (loaded_addon ~= addonName) then return; end
	
	
	self:UnregisterEvent("ADDON_LOADED")
end
	
function addon.events:WORLD_MAP_UPDATE(loaded_addon)
	local mapAreaID = GetCurrentMapAreaID();
	if not InCombatLockdown() then -- and addon.lastMapId ~= mapAreaID then
		BWQ:UpdateQuestList();
		addon.lastMapId = mapAreaID;
	end
end

function addon.events:PLAYER_REGEN_DISABLED(loaded_addon)
	BWQ:ScrollFrameSetEnabled(false)
	ShowOverlayMessage(BWQ_COMBATLOCK);
end

function addon.events:PLAYER_REGEN_ENABLED(loaded_addon)
	if BWQ_WorldQuestFrame:GetAlpha() == 1 then
		BWQ:ScrollFrameSetEnabled(true)
	end
	BWQ_Tab_Onclick(BWQ_WorldQuestFrame.selectedTab);
	BWQ:UpdateQuestList();
end

function addon.events:QUEST_TURNED_IN(loaded_addon)
	if(not _completedQuest and UnitLevel("player") == 110) then
		_completedQuest = GetQuestsCompleted()[43341];
	end
	BWQ:UpdateQuestList();
end

function addon.events:QUEST_WATCH_LIST_CHANGED(loaded_addon)
	BWQ:DisplayQuestList();
end

---------- 
-- Slash
----------

SLASH_BWQSLASH1 = '/wqt';
local function slashcmd(msg, editbox)
	BWQ_Tab_Onclick(BWQ_WorldQuestFrame.selectedTab);
	BWQ:UpdateQuestList();
	
	-- for k, v in pairs(functionCalls)do
		-- print(k, v);
	-- end
end
SlashCmdList["BWQSLASH"] = slashcmd


--------
-- Debug stuff to monitor mem usage
-- Remember to uncomment line template in xml
--------

-- local l_debug = CreateFrame("frame", addonName .. "Debug", UIParent);

-- local function GetDebugLine(lineIndex)
	-- local lineContainer = l_debug.DependencyLines and l_debug.DependencyLines[lineIndex];
	-- if lineContainer then
		-- lineContainer:Show();
		-- return lineContainer;
	-- end
	-- lineContainer = CreateFrame("FRAME", nil, l_debug, "BWQ_DebugLine");

	-- return lineContainer;
-- end

-- local function ShowDebugHistory()
	-- local mem = floor(l_debug.history[#l_debug.history]*100)/100;
	-- for i=1, #l_debug.history-1, 1 do
		-- local line = GetDebugLine(i);
		-- line.Fill:SetStartPoint("BOTTOMLEFT", l_debug, (i-1)*1.4, l_debug.history[i]/10);
		-- line.Fill:SetEndPoint("BOTTOMLEFT", l_debug, i*1.4, l_debug.history[i+1]/10);
		-- line.Fill:SetVertexColor(1, 1, 1);
		-- line.Fill:Show();
	-- end
	-- l_debug.text:SetText(mem)
-- end

-- l_debug:SetBackdrop({bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      -- edgeFile = nil,
	  -- tileSize = 0, edgeSize = 16,
      -- insets = { left = 0, right = 0, top = 0, bottom = 0 }
	  -- })
-- l_debug:SetFrameLevel(5)
-- l_debug:SetMovable(true)
-- l_debug:SetPoint("Center", 250, 0)
-- l_debug:RegisterForDrag("LeftButton")
-- l_debug:EnableMouse(true);
-- l_debug:SetScript("OnDragStart", l_debug.StartMoving)
-- l_debug:SetScript("OnDragStop", l_debug.StopMovingOrSizing)
-- l_debug:SetWidth(100)
-- l_debug:SetHeight(100)
-- l_debug:SetClampedToScreen(true)
-- l_debug.text = l_debug:CreateFontString(nil, nil, "GameFontWhiteSmall")
-- l_debug.text:SetPoint("BOTTOMLEFT", 2, 2)
-- l_debug.text:SetText("0000")
-- l_debug.text:SetJustifyH("left")
-- l_debug.time = 0;
-- l_debug.interval = 0.1;
-- l_debug.history = {}
-- l_debug:SetScript("OnUpdate", function(self,elapsed) 
		-- self.time = self.time + elapsed;
		-- if(self.time >= self.interval) then
			-- self.time = self.time - self.interval;
			-- UpdateAddOnMemoryUsage();
			-- table.insert(self.history, GetAddOnMemoryUsage(addonName));
			-- if(#self.history > 50) then
				-- table.remove(self.history, 1)
			-- end
			-- ShowDebugHistory()
		-- end
	-- end)
-- l_debug:Show()


