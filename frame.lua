module 'aux'

local gui = require 'aux.gui'

function LOAD()
	for _, v in ipairs(tab_info) do
		tabs:create_tab(v.name)
	end
end

do
	local frame = CreateFrame('Frame', 'AuxFrame', UIParent)
	tinsert(UISpecialFrames, 'AuxFrame')
	gui.set_window_style(frame)
	gui.set_size(frame, 768, 447)
	frame:SetPoint('LEFT', 100, 0)
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag('LeftButton')
	frame:SetScript('OnDragStart', function() this:StartMoving() end)
	frame:SetScript('OnDragStop', function() this:StopMovingOrSizing() end)
	frame:SetScript('OnShow', function() PlaySound('AuctionWindowOpen') end)
	frame:SetScript('OnHide', function() PlaySound('AuctionWindowClose'); CloseAuctionHouse() end)
	frame.content = CreateFrame('Frame', nil, frame)
	frame.content:SetPoint('TOPLEFT', 4, -80)
	frame.content:SetPoint('BOTTOMRIGHT', -4, 35)
	frame:Hide()
	M.AuxFrame = frame
end
do
	tabs = gui.tabs(AuxFrame, 'DOWN')
	tabs._on_select = on_tab_click
	function M.set_tab(id) tabs:select(id) end
end
do
	local btn = gui.button(AuxFrame)
	btn:SetPoint('BOTTOMRIGHT', -5, 5)
	gui.set_size(btn, 60, 24)
	btn:SetText('Close')
	btn:SetScript('OnClick', function() AuxFrame:Hide() end)
	close_button = btn
end
do
	local btn = gui.button(AuxFrame, gui.font_size.small)
	btn:SetPoint('RIGHT', close_button, 'LEFT' , -5, 0)
	gui.set_size(btn, 60, 24)
	btn:SetText(color.blizzard'Blizzard UI')
	btn:SetScript('OnClick',function()
		if AuctionFrame:IsVisible() then HideUIPanel(AuctionFrame) else ShowUIPanel(AuctionFrame) end
	end)
	blizzard_ui_button = btn
end
do
	local btn = gui.button(AuxFrame, gui.font_size.small)
	btn:SetPoint('RIGHT', blizzard_ui_button, 'LEFT', -5, 0)
	gui.set_size(btn, 60, 24)
	btn:SetText('Get All')
	btn:SetScript('OnClick', function() require('aux.core.getall').start() end)
	-- a disabled button normally swallows mouse motion; keep motion scripts so the cooldown
	-- tooltip still shows while greyed out.
	btn:SetMotionScriptsWhileDisabled(true)

	local function show_tooltip()
		local getall = require('aux.core.getall')
		GameTooltip:SetOwner(btn, 'ANCHOR_TOP')
		GameTooltip:AddLine('Get All')
		if getall.ready() then
			GameTooltip:AddLine('Scan the entire auction house in a single query.', 1, 1, 1, true)
		else
			local remaining = getall.cooldown_remaining()
			if remaining > 0 then
				GameTooltip:AddLine(format('On cooldown: ready in %d:%02d', floor(remaining / 60), remaining % 60), 1, .3, .3, true)
			else
				GameTooltip:AddLine('Not ready yet (15 minute cooldown).', 1, .3, .3, true)
			end
		end
		GameTooltip:AddLine('Run once a day to keep auction house prices up to date.', .6, .6, .6, true)
		GameTooltip:Show()
	end
	btn:SetScript('OnEnter', show_tooltip)
	btn:SetScript('OnLeave', function() GameTooltip:Hide() end)
	-- readiness only changes on a 15 minute boundary, so poll every 5s to grey/ungrey the button.
	-- While the tooltip is hovered refresh it once a second so the countdown still ticks.
	btn:SetScript('OnUpdate', function()
		local now = GetTime()
		if not this.aux_next_check or now >= this.aux_next_check then
			this.aux_next_check = now + 5
			if require('aux.core.getall').ready() then this:Enable() else this:Disable() end
		end
		if GameTooltip:IsOwned(this) and (not this.aux_next_tip or now >= this.aux_next_tip) then
			this.aux_next_tip = now + 1
			show_tooltip()
		end
	end)
end