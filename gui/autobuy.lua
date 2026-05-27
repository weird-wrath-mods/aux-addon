module 'aux.gui.autobuy'

include 'T'
include 'aux'

local gui = require 'aux.gui'
local money = require 'aux.util.money'
local scan_util = require 'aux.util.scan'
local search = require 'aux.tabs.search'

local frame, item_label, action_button

-- this page's matches, sorted cheapest-first, or nil. PlaceAuctionBid is dropped on Chromie
-- outside a hardware-event context, so the scan parks on each page and the bids fire from this
-- button's clicks. resume_scan advances the parked scan to the next page once we're done here.
local queue
local resume_scan
local bought_this_page -- buyouts fired on the current page; tells the scan whether to re-query it

-- Buy gating. A buyout's PlaceAuctionBid is async; clicking again before it resolves can re-buy
-- an already-bought (in-flight) auction -- a server error plus a double-count. So a click locks
-- the button until the server answers, and the purchase is counted only on a success message
-- (not on click), which keeps accounting correct when a buy is outbid or the item is already gone.
local awaiting        -- the queue entry whose buy is in flight, or nil
local awaiting_amount -- gold committed on that buy, recorded into the summary only once confirmed
local awaiting_since  -- GetTime() of the click, for the no-answer timeout
local BUY_TIMEOUT = 3 -- seconds to wait for a result before unlocking anyway

local won_prefix = (gsub(ERR_AUCTION_WON_S or '', '%%s.*', '')) -- "You won an auction for "
local function is_buy_confirmation(msg)
	return msg == ERR_AUCTION_BID_PLACED -- "Bid accepted."
		or (won_prefix ~= '' and strfind(msg, won_prefix, 1, true) == 1)
end
local function is_buy_failure(msg)
	return msg == ERR_AUCTION_HIGHER_BID
		or msg == ERR_AUCTION_BID_OWN
		or msg == ERR_AUCTION_BID_INCREMENT
		or msg == ERR_NOT_ENOUGH_MONEY
		or msg == ERR_ITEM_NOT_FOUND
end

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
	item_label:SetText(name .. '   x' .. (rec.count or 1) .. '  @ ' .. money.to_string(unit_price(head), true, true))
	action_button:SetText(format('%s   %s   (%d)', head.kind == 'buy' and 'BUYOUT' or 'BID', money.to_string(price(head), true, true), getn(queue)))
end

-- done with this page: hide and resume the parked scan toward the next page
local function finish()
	queue = nil
	if frame then frame:Hide() end
	local r = resume_scan
	resume_scan = nil
	do (r or nop)(bought_this_page or 0) end
end

-- drop the current match; if the page is now empty, move the scan on
local function advance()
	if not queue then return end
	tremove(queue, 1)
	if getn(queue) == 0 then finish() else update_label() end
end

-- the in-flight buy resolved (confirmed by the server, rejected, or timed out): unlock the
-- button, count it into the summary only if it actually went through, then move to the next.
local function resolve(bought)
	local head, amount = awaiting, awaiting_amount
	awaiting, awaiting_amount, awaiting_since = nil, nil, nil
	if action_button then action_button:Enable() end
	if not head then return end
	if bought and head.kind == 'buy' then
		bought_this_page = (bought_this_page or 0) + 1 -- a confirmed buyout shifts the page
		local ps = require 'aux.gui.purchase_summary'
		ps.add_purchase(head.record.name, head.record.texture, head.record.count, amount)
		ps.update_display()
	end
	advance()
end

local function act()
	if awaiting then return end -- a buy is in flight; wait for it to resolve
	local head = queue and queue[1]
	if not head then return end
	local rec, amount = head.record, price(head)
	local idx = locate(rec)
	if not idx or GetMoney() < amount then
		advance() -- already gone from the page, or unaffordable: skip without buying
		return
	end
	awaiting, awaiting_amount, awaiting_since = head, amount, GetTime()
	action_button:Disable() -- lock until the server answers (resolve); blocks a too-fast re-click
	PlaceAuctionBid('list', idx, amount) -- result arrives as a system message / UI error
end

local function ensure_frame()
	if frame then return end

	-- parented to the search results panel so it hides/shows automatically as the user
	-- navigates between subtabs and aux tabs (the panel is only visible on the results page)
	local parent = search.results_panel()
	frame = CreateFrame('Frame', nil, parent)
	frame:SetFrameStrata('DIALOG')
	gui.set_size(frame, 320, 92)
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
	action_button:SetPoint('BOTTOMLEFT', 10, 10)
	action_button:SetPoint('BOTTOMRIGHT', -10, 10)
	action_button:SetHeight(40)
	action_button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
	action_button:SetScript('OnClick', function()
		if awaiting then return end -- locked while a buy is in flight
		if arg1 == 'RightButton' then advance() else act() end
	end)

	frame:SetScript('OnUpdate', function()
		if awaiting and awaiting_since and GetTime() - awaiting_since > BUY_TIMEOUT then
			resolve(false) -- no result arrived in time; unlock without counting (never overcount)
		end
	end)

	frame:Hide()
end

-- present(buys, on_done): show this page's matches; as the user buys/skips them the queue
-- drains, and on_done resumes the scan to the next page once it's empty.
function M.present(buys, on_done)
	ensure_frame()
	awaiting, awaiting_amount, awaiting_since = nil, nil, nil -- fresh page starts unlocked
	action_button:Enable()
	bought_this_page = 0
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
	awaiting, awaiting_amount, awaiting_since = nil, nil, nil
	if action_button then action_button:Enable() end
	if frame then frame:Hide() end
end
M.disarm = disarm

-- a closing AH invalidates the parked page of matches
event_listener('AUCTION_HOUSE_CLOSED', disarm)

-- buy-gate results: only a success message counts the purchase and unlocks the button; an
-- auction error unlocks without counting (outbid / already gone). The frame OnUpdate above
-- covers the case where neither message arrives.
event_listener('CHAT_MSG_SYSTEM', function() if awaiting and is_buy_confirmation(arg1) then resolve(true) end end)
event_listener('UI_ERROR_MESSAGE', function() if awaiting and is_buy_failure(arg1) then resolve(false) end end)
