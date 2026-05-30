module 'aux.core.getall'

local info = require 'aux.util.info'
local history = require 'aux.core.history'

-- A "Get All" scan pulls the entire auction house in one server query (QueryAuctionItems
-- with the getAll flag). The server throttles this (~30 min between getAll queries; the second
-- return of CanSendAuctionQuery is the live gate). Note that flag is client-side and resets on
-- relog, so a relog can let you scan again before the real cooldown elapses. The snapshot stays
-- loaded in the client until the next query.
--
-- Speed model copied from TSM/Auctioneer: during the time-critical read, do the minimum per
-- row -- just pull the raw link + buyout + count and fold the min unit price into a plain
-- table keyed by item. Defer all the expensive history serialisation to a second pass that
-- runs once per UNIQUE item, not once per auction. (history.process_auction only ever lowers
-- daily_min_buyout, so min-unit-price-per-item is the complete contribution.) Both passes are
-- chunked across frames so no single frame stalls. We never call info.auction() here: its
-- tooltip scan + 20-field record build is ~30x the per-row cost and is what made the naive
-- version slow and left the client laggy afterwards.
--
-- Tradeoff: skipping the tooltip means charge items (wands etc.) are priced per stack rather
-- than per charge. Acceptable for a bulk price snapshot.

local COOLDOWN = 15 * 60
local READ_CHUNK = 3000 -- auctions read per frame in phase 1 (cheap per row)
local AGG_CHUNK = 1000   -- unique items folded into history per frame in phase 2 (serialises)
local SNAPSHOT_MIN = 50 -- a getAll puts the whole AH on one page; a leftover browse page is <=50
local DATA_TIMEOUT = 20 -- give up if no data has arrived by now
local READ_DEADLINE = 60 -- give up waiting for never-cached rows after this many seconds

local running = false
local worker -- single reusable OnUpdate frame, created on first use
local bar    -- the active tab's status bar for this run, or nil (then we report to chat)

local function msg(text)
	DEFAULT_CHAT_FRAME:AddMessage('|cffff8800aux:|r ' .. text)
end

-- The status bar of whichever tab is currently shown. Each tab exposes get_status_bar;
-- the inactive tabs' frames are hidden, so only the active tab's bar is :IsVisible (which
-- walks the parent chain, unlike :IsShown). Returns nil if none is visible (e.g. the search
-- tab before any search has run), in which case we fall back to chat.
local STATUS_TABS = {'aux.tabs.post', 'aux.tabs.auctions', 'aux.tabs.bids', 'aux.tabs.search'}
local function visible_status_bar()
	for _, name in ipairs(STATUS_TABS) do
		local module = require(name)
		local status_bar = module.get_status_bar and module.get_status_bar()
		if status_bar and status_bar:IsVisible() then return status_bar end
	end
end

local function report(fraction, text)
	if bar then
		bar:update_status(fraction, fraction)
		bar:set_text(text)
	else
		msg(text)
	end
end

function M.busy()
	return running
end

-- Whether a Get All scan can be started right now. The second return of CanSendAuctionQuery is
-- the authoritative throttle (true only if no getAll in the last 15 min); it survives reloads
-- and relogs because the cooldown is server-side.
function M.ready()
	if running then return false end
	local can_query, can_query_all = CanSendAuctionQuery()
	return (can_query and can_query_all) and true or false
end

-- Seconds left on the cooldown, for display only. Derived from the persisted timestamp of our
-- last scan (aux_getall_last, epoch seconds); 0 if we have no record (e.g. the cooldown was
-- started before this character cached a timestamp). CanSendAuctionQuery remains the real gate.
function M.cooldown_remaining()
	local remaining = COOLDOWN - (time() - (_G.aux_getall_last or 0))
	return remaining > 0 and remaining or 0
end

local function stop()
	if worker then
		worker:SetScript('OnUpdate', nil)
		worker:SetScript('OnEvent', nil)
		worker:UnregisterEvent('AUCTION_ITEM_LIST_UPDATE')
		worker:Hide()
	end
	running = false
end

-- Phase 2: fold each unique item's min unit buyout into the price history, a slice per frame.
local function aggregate(min_buyout, item_count, auction_count, parse_fail, dropped)
	local keys = {}
	for key in pairs(min_buyout) do tinsert(keys, key) end
	local n = getn(keys)
	local i = 0
	local record = {} -- reused; process_auction does not retain it
	worker:SetScript('OnUpdate', function()
		local limit = min(i + AGG_CHUNK, n)
		while i < limit do
			i = i + 1
			local key = keys[i]
			record.item_key, record.buyout_price, record.aux_quantity = key, min_buyout[key], 1
			history.process_auction(record)
		end
		if i >= n then
			stop()
			-- The server caps a getAll reply at MAX_GETALL_RETURN (55000) auctions per its 8MB
			-- packet limit, so on a larger AH we receive fewer than exist. There is no way to
			-- retrieve the remainder (getAll ignores any offset and the cooldown blocks re-runs),
			-- so we just report what we processed rather than flagging an unactionable shortfall.
			report(1, 'Get All complete')
			msg(format('Get All complete: %d items from %d auctions.', item_count, auction_count))
			if (parse_fail or 0) > 0 or (dropped or 0) > 0 then
				msg(format('  diagnostics: %d unreadable links skipped, %d rows dropped uncached.', parse_fail or 0, dropped or 0))
			end
		else
			report(.9 + .1 * i / n, format('Get All: saving %d / %d items', i, n))
		end
	end)
end

-- Phase 1: walk the loaded list, accumulating the min unit buyout per item. Minimal per-row
-- work. Rows whose link/price has not streamed into the client item cache yet are set aside in
-- a retry list rather than stalling the sweep -- blocking on the first not-ready row was what
-- made the counter crawl. The forward sweep therefore finishes in total/READ_CHUNK frames; the
-- retry list is then drained over later frames as the cache fills.
local function read_list()
	-- numBatch = rows actually delivered to the client. The server may deliver fewer than exist
	-- (capped at MAX_GETALL_RETURN); we process whatever arrived, there is no way to get more.
	local total = GetNumAuctionItems('list')
	local min_buyout = {}
	local auction_count, parse_fail = 0, 0

	-- Fold one row into min_buyout. Returns false if its data is not cached yet (link/price nil),
	-- in which case the caller should retry it on a later frame.
	local function try_record(i)
		local link = GetAuctionItemLink('list', i)
		local _, _, count, _, _, _, _, _, buyout = GetAuctionItemInfo('list', i)
		if not (link and count and buyout) then return false end
		if buyout > 0 and count > 0 then
			local item_id, suffix_id = info.parse_link(link)
			-- a link we cannot parse an item id from would collapse into a bogus "0:0" bucket,
			-- merging unrelated items and undercounting them; skip it instead of recording garbage.
			if item_id == 0 then
				parse_fail = parse_fail + 1
			else
				local item_key = item_id .. ':' .. suffix_id
				local unit = ceil(buyout / count)
				if unit < (min_buyout[item_key] or math.huge) then
					min_buyout[item_key] = unit
				end
				auction_count = auction_count + 1
			end
		end
		return true
	end

	local function finish(dropped)
		local item_count = 0
		for _ in pairs(min_buyout) do item_count = item_count + 1 end
		return aggregate(min_buyout, item_count, auction_count, parse_fail, dropped or 0)
	end

	local index, next_chat = 1, 10
	local retry = {}    -- indices waiting on the async item cache
	local deadline      -- set once the forward sweep completes

	report(0, format('Get All: reading %d auctions...', total))
	worker:SetScript('OnUpdate', function()
		-- forward sweep: always advance, deferring not-ready rows to the retry list
		if index <= total then
			local stop_at = min(index + READ_CHUNK, total + 1)
			while index < stop_at do
				if not try_record(index) then tinsert(retry, index) end
				index = index + 1
			end
			if bar then
				report(.9 * (index - 1) / total, format('Get All: %d / %d', index - 1, total))
			else
				local percent = total > 0 and floor((index - 1) / total * 100) or 0
				if percent >= next_chat then
					msg(format('Get All: %d%% (%d / %d)', percent, index - 1, total))
					next_chat = percent - percent % 10 + 10
				end
			end
			return
		end
		-- drain pass: re-check the deferred rows each frame; they resolve as the cache fills.
		-- Anything still missing after READ_DEADLINE is dropped so we cannot hang forever.
		if not deadline then deadline = GetTime() + READ_DEADLINE end
		if getn(retry) == 0 then return finish(0) end
		if GetTime() > deadline then
			-- one last attempt; whatever still will not read is dropped so we cannot hang forever
			local recovered = 0
			for _, i in ipairs(retry) do if try_record(i) then recovered = recovered + 1 end end
			return finish(getn(retry) - recovered)
		end
		local still = {}
		for _, i in ipairs(retry) do
			if not try_record(i) then tinsert(still, i) end
		end
		retry = still
		if getn(retry) == 0 then return finish(0) end
		report(.9, format('Get All: loading %d items...', getn(retry)))
	end)
end

function M.start()
	if running then msg('Get All already in progress.'); return end

	local can_query, can_query_all = CanSendAuctionQuery()
	if not can_query then
		msg('Open the auction house first.')
		return
	end
	if not can_query_all then
		local remaining = ceil(cooldown_remaining())
		if remaining > 0 then
			msg(format('Get All is on cooldown for %d:%02d.', floor(remaining / 60), remaining % 60))
		else
			msg('Get All is throttled right now. Try again shortly.')
		end
		return
	end

	-- A getAll query overwrites the shared 'list' results, so stop any running aux scan first.
	require('aux.core.scan').abort()

	bar = visible_status_bar()
	-- must be _G.-qualified: a bare write in an aux module environment is intercepted as a
	-- module define() (one-shot), which threw "Duplicate identifier" on the second scan. The
	-- _G. prefix writes the real SavedVariable so it also persists across /reload.
	_G.aux_getall_last = time()
	QueryAuctionItems(nil, nil, nil, nil, nil, nil, 0, nil, nil, true)
	report(0, 'Get All: waiting for data...')

	running = true
	worker = worker or CreateFrame('Frame')
	worker:Show()
	local started = GetTime()

	-- Detecting the snapshot: do NOT read on a timer -- the old query's results linger in the
	-- 'list' until the getAll data replaces them, so a timer reads a stale browse page (the
	-- "8 of 208" bug). Instead wait for an AUCTION_ITEM_LIST_UPDATE fired by our query AND for
	-- the batch count to jump to the getAll's single-page size. A leftover browse page is at
	-- most one page (<=50 rows); the getAll delivers the entire AH at once, so numBatch crossing
	-- SNAPSHOT_MIN is the unambiguous signal. (A server-capped getAll still clears this bar.)
	-- Registering the event after the query means we only react to updates caused by it, not a
	-- stale echo from the aborted scan.
	local data_arrived
	worker:RegisterEvent('AUCTION_ITEM_LIST_UPDATE')
	worker:SetScript('OnEvent', function() data_arrived = true end)
	worker:SetScript('OnUpdate', function()
		local numBatch = GetNumAuctionItems('list')
		if data_arrived and numBatch > SNAPSHOT_MIN and GetAuctionItemLink('list', 1) then
			worker:UnregisterEvent('AUCTION_ITEM_LIST_UPDATE')
			worker:SetScript('OnEvent', nil)
			read_list()
		elseif GetTime() - started > DATA_TIMEOUT then
			stop()
			report(1, 'Get All failed: no data')
			msg('Get All failed: no data received (the server may not support it, or you were throttled).')
		end
	end)
end
