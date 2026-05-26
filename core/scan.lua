module 'aux.core.scan'

include 'T'
include 'aux'

local info = require 'aux.util.info'
local history = require 'aux.core.history'
local autobuy = require 'aux.gui.autobuy'

local autobuy_warned -- one-time notice if the gui module hasn't been loaded yet
local pending_buys   -- this page's auto-buy/bid matches, handed to the button at page end

local PAGE_SIZE = 50

do
	local scan_states = {}

	function M.start(params)
		-- only a new 'list' scan supersedes the parked autobuy scan; bidder/owner scans (e.g. the
		-- bids-tab refresh triggered by a buyout) run on different data and must not clear the queue
		if params.type == 'list' then (autobuy.disarm or nop)() end
		if (params.auto_buy_validator or params.auto_bid_validator) and not autobuy.present and not autobuy_warned then
			autobuy_warned = true
			DEFAULT_CHAT_FRAME:AddMessage('|cffff8800aux:|r Auto-Buy module not loaded yet. Fully restart the client (exit to desktop), not just /reload.')
		end
		local old_state = scan_states[params.type]
		if old_state then
			abort(old_state.id)
		end
		do (params.on_scan_start or nop)() end
		local thread_id = thread(scan)
		scan_states[params.type] = {
			id = thread_id,
			params = params,
		}
		return thread_id
	end

	function M.abort(scan_id)
		local aborted = T
		for type, state in pairs(scan_states) do
			if not scan_id or state.id == scan_id then
				kill_thread(state.id)
				-- a scan aborted mid-page leaves its AUCTION_ITEM_LIST_UPDATE listener parked
				-- (it's only killed when the page is accepted); kill it here so it doesn't keep
				-- firing for the rest of the session.
				if state.result_listener then kill_listener(state.result_listener) end
				scan_states[type] = nil
				tinsert(aborted, state)
			end
		end
		for _, state in pairs(aborted) do
			do (state.params.on_abort or nop)() end
		end
	end

	function M.stop()
		state.stopped = true
	end

	function complete()
		local on_complete = state.params.on_complete
		scan_states[state.params.type] = nil
		do (on_complete or nop)() end
	end

	function get_state()
		for _, state in pairs(scan_states) do
			if state.id == thread_id then
				return state
			end
		end
	end
end

function get_query()
	if state.params.type == 'list' then
		return state.params.queries[state.query_index]
	else
		return empty
	end
end

function total_pages(total_auctions)
    return ceil(total_auctions / PAGE_SIZE)
end

function last_page(total_auctions)
    local last_page = max(total_pages(total_auctions) - 1, 0)
    local last_page_limit = query.blizzard_query.last_page or last_page
    return min(last_page_limit, last_page)
end

function scan()
	if state.params.type ~= 'list' then
		return scan_page()
	end

	state.query_index = state.query_index and state.query_index + 1 or 1
	if query and not state.stopped then
		do (state.params.on_start_query or nop)(state.query_index) end
		if query.blizzard_query then
			if (query.blizzard_query.first_page or 0) <= (query.blizzard_query.last_page or huge) then
				state.page = query.blizzard_query.first_page or 0
				return submit_query()
			end
		else
			state.page = nil
			return scan_page()
		end
	end
	return complete()
end

do
	local function submit()
		state.last_list_query = GetTime()
		local blizzard_query = query.blizzard_query or T
		QueryAuctionItems(
			blizzard_query.name,
			blizzard_query.min_level,
			blizzard_query.max_level,
			blizzard_query.slot,
			blizzard_query.class,
			blizzard_query.subclass,
			state.page,
			blizzard_query.usable,
			blizzard_query.quality
		)
		return wait_for_results()
	end
	function submit_query()
		if state.stopped then return end
		return when(CanSendAuctionQuery, submit)
	end
end

function advance_page()
	if query.blizzard_query and state.page < last_page(state.total_auctions) then
		state.page = state.page + 1
		return submit_query()
	else
		return scan()
	end
end

function page_done()
	-- present this page's matches and park; the user buys/skips them (or hits Next page),
	-- then the button resumes the scan to the next page. Parking keeps the page loaded so the
	-- indices stay valid. Pages with no matches advance immediately (no user wait).
	if autobuy.present and getn(pending_buys) > 0 then
		local send_signal, signal_received = signal()
		-- buying deletes auctions and shifts everything below up a slot, so rows that were just
		-- past this page move into it (and the shrinking total can otherwise cut the scan short).
		-- Re-query the SAME page after any purchase to catch them; only advance once the user
		-- goes through a page buying nothing. send_signal carries the count bought this page.
		when(signal_received, function()
			local bought = signal_received()
			if bought and bought[1] and bought[1] > 0 then
				return submit_query() -- re-query the same page; buying shifted later rows into it
			end
			return advance_page()
		end)
		return autobuy.present(pending_buys, send_signal)
	end
	return advance_page()
end

function scan_page(i)
	i = i or 1
	if i == 1 then pending_buys = T end

	if not state.page then
		_,  state.total_auctions = GetNumAuctionItems(state.params.type)
	end

	if state.params.type == 'list' and i > PAGE_SIZE then
		do (state.params.on_page_scanned or nop)() end
		return page_done()
	elseif state.params.type ~= 'list' and i > state.total_auctions then
		return complete()
	end

	local auction_info = info.auction(i, state.params.type)
	if auction_info and (auction_info.owner or state.params.ignore_owner or aux_ignore_owner) then
		auction_info.index = i
		auction_info.page = state.page
		auction_info.blizzard_query = query.blizzard_query
		auction_info.query_type = state.params.type

		history.process_auction(auction_info)

		-- auto-buy/bid: collect this page's matches for the button (presented at page end)
		local autobuy_match
		if autobuy.present
			and (state.params.auto_buy_validator or nop)(auction_info)
			and auction_info.buyout_price > 0
			and auction_info.owner ~= UnitName('player') then
			tinsert(pending_buys, O('kind', 'buy', 'record', copy(auction_info)))
			autobuy_match = true
		elseif autobuy.present
			and (state.params.auto_bid_validator or nop)(auction_info)
			and auction_info.owner ~= UnitName('player')
			and auction_info.high_bidder == nil then
			tinsert(pending_buys, O('kind', 'bid', 'record', copy(auction_info)))
			autobuy_match = true
		end
		if not autobuy_match and (not query.validator or query.validator(auction_info)) then
			do (state.params.on_auction or nop)(auction_info) end
		end
	end

	return scan_page(i + 1)
end

function accept_results()
	_,  state.total_auctions = GetNumAuctionItems(state.params.type)
	do
		(state.params.on_page_loaded or nop)(
			state.page - (query.blizzard_query.first_page or 0) + 1,
			last_page(state.total_auctions) - (query.blizzard_query.first_page or 0) + 1,
			total_pages(state.total_auctions) - 1
		)
	end
	return scan_page()
end

local SETTLE_WAIT = 0.4 -- accept a page only after the list has been quiet this long
local MIN_WAIT = 0.3    -- ...and never sooner than this after the query (skip the instant stale echo)

function wait_for_results()
    local last_update
    local listener_id = event_listener('AUCTION_ITEM_LIST_UPDATE', function()
        last_update = GetTime()
    end)
    state.result_listener = listener_id -- so an abort mid-wait can kill it (see M.abort)
    local timeout = later(5, state.last_list_query)
    local ignore_owner = state.params.ignore_owner or aux_ignore_owner
	return when(function()
		-- no data at all within the hard timeout: give up and re-submit the query
		if not last_update and timeout() then
			return true
		end
		-- hard cap: take whatever we have if the list never settles
		if last_update and GetTime() - state.last_list_query >= 5 then
			return true
		end
		-- The first AUCTION_ITEM_LIST_UPDATE after a query can be a stale snapshot: the prior
		-- query's data echoed back, or this query's rows before prices settle. The real data
		-- lands a moment later. Accept only once the page looks complete AND the list has gone
		-- quiet for SETTLE_WAIT (and at least MIN_WAIT has passed), so we read the settled data
		-- rather than the first stale frame. ignore_owner only skips the slow owner field.
		if last_update
			and GetTime() - state.last_list_query >= MIN_WAIT
			and GetTime() - last_update >= SETTLE_WAIT
			and page_complete(ignore_owner) then
			return true
		end
	end, function()
		kill_listener(listener_id)
		state.result_listener = nil
		if not last_update and timeout() then
			return submit_query()
		else
			return accept_results()
		end
	end)
end

-- A page's rows stream in over several AUCTION_ITEM_LIST_UPDATE events. The batch count from
-- GetNumAuctionItems is correct from the first update, but per-row data (link/name, prices)
-- lags. Accepting before every row has loaded silently drops the not-yet-loaded rows (their
-- GetAuctionItemInfo name is nil, so info.auction returns nil and the validators never see
-- them) -- which is why a re-scan finds matches the first scan missed. Owner is the slowest
-- field and the only thing aux_ignore_owner is meant to skip, so we still gate on it here.
function page_complete(ignore_owner)
    local batch = GetNumAuctionItems(state.params.type)
    for i = 1, batch do
        local name, _, _, _, _, _, _, _, _, _, _, owner = GetAuctionItemInfo(state.params.type, i)
        if not name then
            return false
        end
        if not ignore_owner and not owner then
            return false
        end
    end
    return true
end