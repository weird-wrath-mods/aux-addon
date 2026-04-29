module 'aux.gui.purchase_summary'

include 'T'
include 'aux'

local money = require 'aux.util.money'
local gui = require 'aux.gui'

-- Per-session purchase tally: { item_name -> { texture, total_quantity, total_cost, purchase_count } }
local purchase_summaries = {}

-- Lazy-created display frame, anchored above AuxFrame.
local purchase_summary_frame

function M.get_summaries()
	return purchase_summaries
end

function M.clear_summaries()
	wipe(purchase_summaries)
end

function M.add_purchase(name, texture, quantity, cost)
	if not name then return end
	if not purchase_summaries[name] then
		purchase_summaries[name] = {
			item_name = name,
			texture = texture or '',
			total_quantity = 0,
			total_cost = 0,
			purchase_count = 0,
		}
	end
	local s = purchase_summaries[name]
	s.total_quantity = s.total_quantity + (quantity or 0)
	s.total_cost = s.total_cost + (cost or 0)
	s.purchase_count = s.purchase_count + 1
end

local function create_purchase_summary_frame()
	if purchase_summary_frame then return purchase_summary_frame end

	local f = CreateFrame('Frame', 'AuxPurchaseSummary', UIParent)
	f:SetWidth(300)
	f:SetHeight(100)
	local y_offset = gui.is_blizzard and gui.is_blizzard() and 9 or -2
	f:SetPoint('BOTTOM', AuxFrame, 'TOP', 0, y_offset)
	f:SetFrameLevel(AuxFrame:GetFrameLevel())
	gui.set_panel_style(f, 2, 2, 2, 2)
	f:Hide()

	-- Click to copy as plain text via StaticPopup edit box.
	f:EnableMouse(true)
	f:SetScript('OnMouseDown', function()
		local summary_text = M.format_summary_as_text()
		StaticPopupDialogs['AUX_PURCHASE_SUMMARY_COPY'] = {
			text = 'Purchase Summary (Click to select all, then Ctrl+C to copy):',
			button1 = 'OK',
			hasEditBox = true,
			OnShow = function()
				local editBox = getglobal(this:GetName() .. 'EditBox')
				editBox:SetText(summary_text)
				editBox:HighlightText()
			end,
			EditBoxOnEscapePressed = function()
				this:GetParent():Hide()
			end,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
		}
		StaticPopup_Show('AUX_PURCHASE_SUMMARY_COPY')
	end)

	local title = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	title:SetPoint('TOPLEFT', 8, -8)
	title:SetText('Purchase Summary')
	title:SetTextColor(color.label.enabled())
	f.title = title

	local total_spent_text = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	total_spent_text:SetPoint('TOPLEFT', 208, -8)
	total_spent_text:SetWidth(80)
	total_spent_text:SetJustifyH('RIGHT')
	total_spent_text:SetTextColor(color.label.enabled())
	f.total_spent_text = total_spent_text

	local header_item = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	header_item:SetPoint('TOPLEFT', title, 'BOTTOMLEFT', 0, -4)
	header_item:SetWidth(150)
	header_item:SetJustifyH('LEFT')
	header_item:SetText('Item')
	header_item:SetTextColor(color.label.enabled())
	f.header_item = header_item

	local header_count = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	header_count:SetPoint('LEFT', header_item, 'RIGHT', 5, 0)
	header_count:SetWidth(40)
	header_count:SetJustifyH('RIGHT')
	header_count:SetText('Count')
	header_count:SetTextColor(color.label.enabled())
	f.header_count = header_count

	local header_cost = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	header_cost:SetPoint('LEFT', header_count, 'RIGHT', 5, 0)
	header_cost:SetWidth(80)
	header_cost:SetJustifyH('RIGHT')
	header_cost:SetText('Gold Spent')
	header_cost:SetTextColor(color.label.enabled())
	f.header_cost = header_cost

	f.rows = {}
	purchase_summary_frame = f
	return f
end

local function summary_count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

function M.update_display()
	local f = create_purchase_summary_frame()

	if aux_purchase_summary == false then
		f:Hide()
		return
	end

	if summary_count(purchase_summaries) == 0 then
		f:Hide()
		return
	end

	local total_spent = 0
	for _, s in pairs(purchase_summaries) do
		total_spent = total_spent + (s.total_cost or 0)
	end

	if total_spent > 0 then
		local cost = total_spent >= 10000 and floor(total_spent / 100) * 100 or total_spent
		f.total_spent_text:SetText(money.to_string(cost, nil, true))
		f.total_spent_text:Show()
	else
		f.total_spent_text:Hide()
	end

	for _, row in pairs(f.rows) do row:Hide() end

	local row_count = 0
	for item_name, summary in pairs(purchase_summaries) do
		row_count = row_count + 1

		if not f.rows[row_count] then
			local row = CreateFrame('Frame', nil, f)
			row:SetHeight(14)
			row:SetWidth(260)

			local item_text = row:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
			item_text:SetPoint('TOPLEFT', row, 'TOPLEFT', 0, 0)
			item_text:SetWidth(150)
			item_text:SetJustifyH('LEFT')
			item_text:SetTextColor(color.text.enabled())
			row.item_text = item_text

			local count_text = row:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
			count_text:SetPoint('TOPLEFT', row, 'TOPLEFT', 155, 0)
			count_text:SetWidth(40)
			count_text:SetJustifyH('RIGHT')
			count_text:SetTextColor(color.text.enabled())
			row.count_text = count_text

			local cost_text = row:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
			cost_text:SetPoint('TOPLEFT', row, 'TOPLEFT', 200, 0)
			cost_text:SetWidth(80)
			cost_text:SetJustifyH('RIGHT')
			cost_text:SetTextColor(color.text.enabled())
			row.cost_text = cost_text

			f.rows[row_count] = row
		end

		local row = f.rows[row_count]
		if row_count == 1 then
			row:SetPoint('TOPLEFT', f.header_item, 'BOTTOMLEFT', 0, -2)
		else
			row:SetPoint('TOPLEFT', f.rows[row_count - 1], 'BOTTOMLEFT', 0, 0)
		end

		row.item_text:SetText(item_name)
		row.count_text:SetText(summary.total_quantity .. 'x')

		local cost = summary.total_cost or 0
		local display_cost = cost >= 10000 and floor(cost / 100) * 100 or cost
		row.cost_text:SetText(money.to_string(display_cost, nil, true))
		row:Show()
	end

	local estimated_height = 44 + (row_count * 14)
	f:SetHeight(max(60, estimated_height))
	f:Show()
end

function M.hide()
	if purchase_summary_frame then
		purchase_summary_frame:Hide()
	end
end

function M.format_summary_as_text()
	if summary_count(purchase_summaries) == 0 then
		return 'No purchases made.'
	end

	local lines = {}
	local player_name = UnitName('player')
	local item_names = {}
	local total_spent = 0

	local date_table = date('*t')
	local date_string = format('%d/%d/%d', date_table.year, date_table.month, date_table.day)

	for item_name, summary in pairs(purchase_summaries) do
		local cost = summary.total_cost or 0
		total_spent = total_spent + cost
		tinsert(lines, format('%s\t%d\t%s\t%s', item_name, summary.total_quantity, player_name, date_string))
		tinsert(item_names, item_name)
	end

	local total_gold = -total_spent / 10000
	local items_list = table.concat(item_names, ',')
	tinsert(lines, format('Gold\t%.2f\t%s\t%s\t%s', total_gold, player_name, date_string, items_list))

	return table.concat(lines, '\n')
end

-- Hide and reset on AH close.
event_listener('AUCTION_HOUSE_CLOSED', function()
	if purchase_summary_frame then
		purchase_summary_frame:Hide()
	end
	wipe(purchase_summaries)
end)
