module 'aux.gui.autobuy'

include 'T'
include 'aux'

local gui = require 'aux.gui'
local money = require 'aux.util.money'
local scan_util = require 'aux.util.scan'

local frame, item_label, action_button

-- queue of O('kind', 'record') for the current page, sorted cheapest-first, or nil.
-- PlaceAuctionBid is dropped on Chromie unless it runs in a hardware-event context, so the
-- scan parks on a page's matches and the actual bids fire from this button's clicks.
local queue
local resume_scan -- continues the parked scan once the queue is drained

local function unit_price(entry)
	return entry.kind == 'buy' and entry.record.unit_buyout_price or entry.record.unit_bid_price
end

local function price(entry)
	return entry.kind == 'buy' and entry.record.buyout_price or entry.record.bid_price
end

-- index of this auction on the currently loaded page; the stored index is tried first
-- (valid between rapid clicks, since the client list isn't re-indexed until a re-query),
-- then a local fallback scan handles any shift. No server round-trip either way.
local function locate(record)
	if scan_util.test(record, record.index) then return record.index end
	for idx = 1, 50 do
		if scan_util.test(record, idx) then return idx end
	end
end

local function update_label()
	local head = queue and queue[1]
	if not head then return end
	local rec = head.record
	local q = ITEM_QUALITY_COLORS[rec.quality]
	local name = (q and q.hex or '') .. (rec.name or '?') .. (q and FONT_COLOR_CODE_CLOSE or '')
	item_label:SetText(name .. '   x' .. (rec.count or 1))
	action_button:SetText(format('%s   %s   (%d)', head.kind == 'buy' and 'BUYOUT' or 'BID', money.to_string(price(head), true, true), getn(queue)))
end

local function finish()
	queue = nil
	if frame then frame:Hide() end
	local r = resume_scan
	resume_scan = nil
	do (r or nop)() end
end

local function advance()
	tremove(queue, 1)
	if getn(queue) == 0 then finish() else update_label() end
end

local function act()
	local head = queue and queue[1]
	if not head then return end
	local rec, amount = head.record, price(head)
	local idx = locate(rec)
	if idx and GetMoney() >= amount then
		PlaceAuctionBid('list', idx, amount) -- direct: hardware event, no lock, rapid-fireable
		if head.kind == 'buy' then
			local ps = require 'aux.gui.purchase_summary'
			ps.add_purchase(rec.name, rec.texture, rec.count, amount)
			ps.update_display()
		end
	end
	advance() -- bought, gone, or unaffordable: always move to the next match
end

local function ensure_frame()
	if frame then return end

	frame = CreateFrame('Frame', nil, AuxFrame.content)
	frame:SetFrameStrata('DIALOG')
	gui.set_size(frame, 320, 92)
	frame:SetPoint('CENTER', AuxFrame.content, 'CENTER', 0, 0)
	gui.set_window_style(frame)

	local title = gui.label(frame, gui.font_size.small)
	title:SetPoint('TOPLEFT', 8, -7)
	title:SetPoint('TOPRIGHT', -8, -7)
	title:SetJustifyH('CENTER')
	title:SetText('left-click buy (cheapest first)  /  right-click skip')

	item_label = gui.label(frame, gui.font_size.medium)
	item_label:SetPoint('TOPLEFT', 8, -25)
	item_label:SetPoint('TOPRIGHT', -8, -25)
	item_label:SetJustifyH('CENTER')

	action_button = gui.button(frame, gui.font_size.large)
	action_button:SetPoint('BOTTOMLEFT', 10, 10)
	action_button:SetPoint('BOTTOMRIGHT', -10, 10)
	action_button:SetHeight(40)
	action_button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
	action_button:SetScript('OnClick', function()
		if arg1 == 'RightButton' then advance() else act() end
	end)

	frame:Hide()
end

-- present(buys, on_done): buys = list of O('kind', 'record'). Shows the button and lets the
-- user rapid-fire through the page's matches cheapest-first; on_done resumes the scan when drained.
function M.present(buys, on_done)
	ensure_frame()
	queue = buys
	sort(queue, function(a, b) return unit_price(a) < unit_price(b) end)
	resume_scan = on_done
	update_label()
	frame:Show()
	frame:Raise()
end

function M.disarm()
	queue = nil
	resume_scan = nil -- a superseding scan owns continuation now; don't resume the old one
	if frame then frame:Hide() end
end

-- a closing AH invalidates any parked page of matches
event_listener('AUCTION_HOUSE_CLOSED', function() M.disarm() end)
