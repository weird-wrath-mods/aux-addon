module 'aux.gui.autobuy'

include 'T'
include 'aux'

local gui = require 'aux.gui'
local money = require 'aux.util.money'
local scan_util = require 'aux.util.scan'
local search = require 'aux.tabs.search'

local frame, item_label, action_button, next_button

-- this page's matches, sorted cheapest-first, or nil. PlaceAuctionBid is dropped on Chromie
-- outside a hardware-event context, so the scan parks on each page and the bids fire from this
-- button's clicks. resume_scan advances the parked scan to the next page once we're done here.
local queue
local resume_scan

local function unit_price(entry)
	return entry.kind == 'buy' and entry.record.unit_buyout_price or entry.record.unit_bid_price
end

local function price(entry)
	return entry.kind == 'buy' and entry.record.buyout_price or entry.record.bid_price
end

-- current index of this auction on the loaded page; stored index first (valid between clicks,
-- the client list isn't re-indexed until a re-query), then a local fallback scan after a shift.
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

-- done with this page: hide and resume the parked scan toward the next page
local function finish()
	queue = nil
	if frame then frame:Hide() end
	local r = resume_scan
	resume_scan = nil
	do (r or nop)() end
end

-- drop the current match; if the page is now empty, move the scan on
local function advance()
	if not queue then return end
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

	-- parented to the search results panel so it hides/shows automatically as the user
	-- navigates between subtabs and aux tabs (the panel is only visible on the results page)
	local parent = search.results_panel()
	frame = CreateFrame('Frame', nil, parent)
	frame:SetFrameStrata('DIALOG')
	gui.set_size(frame, 320, 116)
	frame:SetPoint('CENTER', parent, 'CENTER', 0, 0)
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
	action_button:SetPoint('TOPLEFT', 10, -44)
	action_button:SetPoint('TOPRIGHT', -10, -44)
	action_button:SetHeight(38)
	action_button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
	action_button:SetScript('OnClick', function()
		if arg1 == 'RightButton' then advance() else act() end
	end)

	next_button = gui.button(frame, gui.font_size.medium)
	next_button:SetPoint('BOTTOMLEFT', 10, 8)
	next_button:SetPoint('BOTTOMRIGHT', -10, 8)
	next_button:SetHeight(22)
	next_button:SetText('Next page >>')
	next_button:SetScript('OnClick', finish) -- abandon this page's leftovers, scan the next

	frame:Hide()
end

-- present(buys, on_done): show this page's matches; the user buys/skips them or hits Next page,
-- then on_done resumes the scan to the next page (called automatically when the queue empties).
function M.present(buys, on_done)
	ensure_frame()
	queue = buys
	sort(queue, function(a, b) return unit_price(a) < unit_price(b) end)
	resume_scan = on_done
	update_label()
	frame:Show()
	frame:Raise()
end

local function disarm()
	queue = nil
	resume_scan = nil -- a superseding scan owns continuation now; don't resume the old one
	if frame then frame:Hide() end
end
M.disarm = disarm

-- a closing AH invalidates the parked page of matches
event_listener('AUCTION_HOUSE_CLOSED', disarm)
