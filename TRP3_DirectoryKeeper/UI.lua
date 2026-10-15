-- TRP3 Directory Keeper
-- Import and Export buttons in Total RP 3's directory, and the confirmation popups.
--
-- The buttons are added next to the search button of the Characters tab's filter panel, using
-- TRP3's own icon button template and the search button's scale, so they look like TRP3's buttons.
-- If a TRP3 update renames that panel the buttons are simply not added; /tdk import and
-- /tdk export keep working.

local _, ns = ...

local UI = {}
ns.UI = UI

local IMPORT_ICON = 4200127 -- misc_rnrwrenchbuttonleft
local EXPORT_ICON = 4200128 -- misc_rnrwrenchbuttonright
local BUTTON_SPACING = -6

---------------------------------------------------------------------------
-- Popups
---------------------------------------------------------------------------

local function RunCallback(data, key)
	if type(data) == "table" and type(data[key]) == "function" then
		data[key]()
	end
end

StaticPopupDialogs["TRP3DK_CONFIRM"] = {
	text = "%s",
	button1 = ACCEPT,
	button2 = CANCEL,
	OnAccept = function(_, data) RunCallback(data, "onAccept") end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["TRP3DK_RELOAD"] = {
	text = "%s",
	button1 = "Reload",
	button2 = "Later",
	OnAccept = function() ReloadUI() end,
	OnCancel = function() ns.Print("The file will be written at your next reload or logout.") end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["TRP3DK_IMPORT_CHECK"] = {
	text = "%s",
	button1 = "Import",
	button2 = CANCEL,
	OnAccept = function(_, data) RunCallback(data, "onAccept") end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["TRP3DK_IMPORT_APPLY"] = {
	text = "%s",
	button1 = "Reload",
	button2 = CANCEL,
	OnAccept = function(_, data) RunCallback(data, "onAccept") end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["TRP3DK_ALERT"] = {
	text = "%s",
	button1 = OKAY,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function UI.Confirm(text, onAccept)
	StaticPopup_Show("TRP3DK_CONFIRM", text, nil, { onAccept = onAccept })
end

function UI.ConfirmReload(text)
	StaticPopup_Show("TRP3DK_RELOAD", text)
end

function UI.AskImportReady(text, onYes)
	StaticPopup_Show("TRP3DK_IMPORT_CHECK", text, nil, { onAccept = onYes })
end

--- Last step of an import: "Reload" adds the entries and reloads, "Cancel" imports nothing.
function UI.ConfirmImport(text, onAccept)
	StaticPopup_Show("TRP3DK_IMPORT_APPLY", text, nil, { onAccept = onAccept })
end

function UI.Alert(text)
	StaticPopup_Show("TRP3DK_ALERT", text)
end

---------------------------------------------------------------------------
-- Directory buttons
---------------------------------------------------------------------------

local function SetTooltip(button, title, text)
	local tooltip = TRP3_API and TRP3_API.ui and TRP3_API.ui.tooltip
	if tooltip and tooltip.setTooltipForSameFrame then
		tooltip.setTooltipForSameFrame(button, "TOP", 0, 5, title, text)
	end
end

local function CreateIconButton(name, parent, scale, icon)
	local button = CreateFrame("Button", name, parent, "TRP3_IconButton")
	button:SetScale(scale)
	button.Icon:SetTexture(icon)
	return button
end

--- Adds the buttons to TRP3's directory. Returns false when TRP3's panel was not found.
function UI.CreateDirectoryButtons()
	if UI.buttonsCreated then return true end
	local panel = _G.TRP3_RegisterListCharactFilter
	local searchButton = _G.TRP3_RegisterListCharactFilterButton
	if not (panel and searchButton) then
		return false
	end
	local scale = searchButton:GetScale()

	local exportButton = CreateIconButton("TRP3DK_ExportButton", panel, scale, EXPORT_ICON)
	exportButton:SetPoint("RIGHT", searchButton, "LEFT", BUTTON_SPACING, 0)
	SetTooltip(exportButton, "Export directory",
		"Saves your whole directory to a file you can send to other players.|n|nYour ignore list is not included.")
	exportButton:SetScript("OnClick", function() ns.Exchange.StartExport() end)

	local importButton = CreateIconButton("TRP3DK_ImportButton", panel, scale, IMPORT_ICON)
	importButton:SetPoint("RIGHT", exportButton, "LEFT", BUTTON_SPACING, 0)
	SetTooltip(importButton, "Import directory",
		"Adds the characters from a received export file that are not in your directory yet.|n|nCharacters you already have are never changed.")
	importButton:SetScript("OnClick", function() ns.Exchange.StartImport() end)

	UI.buttonsCreated = true
	return true
end
