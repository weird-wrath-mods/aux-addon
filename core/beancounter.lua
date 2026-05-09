module 'aux.core.beancounter'

include 'aux'

local BUCKETS = {
	'completedAuctions', 'failedAuctions',
	'completedBidsBuyouts', 'failedBids',
}

local function realm() return GetRealmName() end
local function me()    return UnitName('player') end

local function player_db(player)
	if not _G.BeanCounterDB then return end
	local r = _G.BeanCounterDB[realm()]
	if not r then return end
	return r[player or me()]
end

function M.available()
	return player_db() ~= nil
end

local function unpack_entry(text)
	if not text then return end
	local stack, money, deposit, fee, buyout, bid, buyer, t, reason, meta = strsplit(';', text)
	return {
		stack   = tonumber(stack)   or 0,
		money   = tonumber(money)   or 0,
		deposit = tonumber(deposit) or 0,
		fee     = tonumber(fee)     or 0,
		buyout  = tonumber(buyout)  or 0,
		bid     = tonumber(bid)     or 0,
		buyer   = (buyer ~= '' and buyer ~= '0') and buyer or nil,
		time    = tonumber(t)       or 0,
		reason  = (reason ~= '' and reason ~= '0') and reason or nil,
		meta    = meta,
	}
end

function M.entries(item_id, bucket, player)
	local db = player_db(player)
	if not db or not db[bucket] or not db[bucket][item_id] then return {} end
	local out = {}
	for itemstring, list in pairs(db[bucket][item_id]) do
		for _, raw in ipairs(list) do
			local e = unpack_entry(raw)
			if e then
				e.bucket = bucket
				e.itemstring = itemstring
				tinsert(out, e)
			end
		end
	end
	return out
end

function M.all_entries(item_id, player)
	local out = {}
	for _, b in ipairs(BUCKETS) do
		for _, e in ipairs(entries(item_id, b, player)) do
			tinsert(out, e)
		end
	end
	table.sort(out, function(a, b) return a.time > b.time end)
	return out
end

function M.sold_failed(item_id, days, player)
	if not item_id then return end
	local cutoff = days and (time() - days * 86400) or 0
	local ok, fail, ok_stk, fail_stk = 0, 0, 0, 0
	for _, e in ipairs(entries(item_id, 'completedAuctions', player)) do
		if e.time >= cutoff then ok = ok + 1; ok_stk = ok_stk + e.stack end
	end
	for _, e in ipairs(entries(item_id, 'failedAuctions', player)) do
		if e.time >= cutoff then fail = fail + 1; fail_stk = fail_stk + e.stack end
	end
	return ok, fail, ok_stk, fail_stk
end

function M.last_buy(item_id, quantity, player)
	if not item_id then return end
	local best
	for _, e in ipairs(entries(item_id, 'completedBidsBuyouts', player)) do
		if (not quantity or e.stack == quantity) and (not best or e.time > best.time) then
			best = e
		end
	end
	return best
end

function M.last_sell(item_id, quantity, player)
	if not item_id then return end
	local best
	for _, e in ipairs(entries(item_id, 'completedAuctions', player)) do
		if (not quantity or e.stack == quantity) and (not best or e.time > best.time) then
			best = e
		end
	end
	return best
end
