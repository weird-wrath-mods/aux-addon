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

local function blank(v)
	if v == nil or v == 0 or v == '' or v == '0' or v == '<nil>' then return '' end
	if v == true then return 'boolean true' end
	if v == false then return 'boolean false' end
	return tostring(v)
end

function M.pack(stack, money, deposit, fee, buyout, bid, buyer, t, reason, meta)
	return blank(stack) .. ';' .. blank(money) .. ';' .. blank(deposit) .. ';' ..
	       blank(fee)   .. ';' .. blank(buyout) .. ';' .. blank(bid) .. ';' ..
	       blank(buyer) .. ';' .. blank(t) .. ';' .. blank(reason) .. ';' .. blank(meta)
end

local function ensure_db()
	if not _G.BeanCounterDB then _G.BeanCounterDB = {} end
	local r = _G.BeanCounterDB
	if not r[realm()] then r[realm()] = {} end
	if not r[realm()][me()] then
		r[realm()][me()] = {
			postedAuctions = {}, completedAuctions = {}, failedAuctions = {},
			postedBids = {}, completedBidsBuyouts = {}, failedBids = {},
			vendorbuy = {}, vendorsell = {},
		}
	end
	if not _G.BeanCounterDBNames then _G.BeanCounterDBNames = {} end
	return r[realm()][me()]
end

function M.db_add(bucket, item_id, itemstring, packed)
	if not item_id or not itemstring or not packed then return end
	local db = ensure_db()
	if not db[bucket] then db[bucket] = {} end
	if not db[bucket][item_id] then db[bucket][item_id] = {} end
	if not db[bucket][item_id][itemstring] then db[bucket][item_id][itemstring] = {} end
	tinsert(db[bucket][item_id][itemstring], packed)
end

function M.db_remove(bucket, item_id, itemstring, predicate)
	local db = _G.BeanCounterDB and _G.BeanCounterDB[realm()] and _G.BeanCounterDB[realm()][me()]
	if not db or not db[bucket] or not db[bucket][item_id] or not db[bucket][item_id][itemstring] then return end
	local list = db[bucket][item_id][itemstring]
	for i = getn(list), 1, -1 do
		if predicate(list[i], i) then
			tremove(list, i)
			return true
		end
	end
end

function M.db_list(bucket, item_id, itemstring)
	local db = _G.BeanCounterDB and _G.BeanCounterDB[realm()] and _G.BeanCounterDB[realm()][me()]
	if not db or not db[bucket] or not db[bucket][item_id] or not db[bucket][item_id][itemstring] then return T end
	return db[bucket][item_id][itemstring]
end

function M.unpack(text)
	return unpack_entry(text)
end

function M.bc_itemstring(item_link)
	if not item_link then return end
	local _, _, s = strfind(item_link, 'H(item:[^|]+)|h')
	if not s then return end
	return (gsub(s, '(item:[^:]+:[^:]+:[^:]+:[^:]+:[^:]+:[^:]+:[^:]+:[^:]+):%-?%d+', '%1:80'))
end

function M.store_link(item_link)
	if not item_link then return end
	local _, _, hex, item_id, suffix, name = strfind(item_link,
		'|(c%x%x%x%x%x%x%x%x)|Hitem:(%d+):%d+:%d+:%d+:%d+:%d+:(%-?%d+):.-|h%[(.-)%]')
	if hex and item_id and suffix and name then
		_G.BeanCounterDBNames = _G.BeanCounterDBNames or {}
		_G.BeanCounterDBNames[item_id .. ':' .. suffix] = hex .. ';' .. name
	end
end
