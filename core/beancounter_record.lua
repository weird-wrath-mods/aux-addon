module 'aux.core.beancounter_record'

include 'T'
include 'aux'

local info = require 'aux.util.info'
local bc = require 'aux.core.beancounter'

local pending_posts = {}
local pending_bids  = {}
local last_multi    = {}

local function find_locked_item()
	for bag = 0, 4 do
		for slot = 1, GetContainerNumSlots(bag) do
			local _, count, locked = GetContainerItemInfo(bag, slot)
			if locked then
				return GetContainerItemLink(bag, slot), count or 0
			end
		end
	end
end

local function add_pending_post(link, name, count, min_bid, buyout, run_time, deposit)
	tinsert(pending_posts, {
		link = link, name = name, count = count,
		min_bid = min_bid, buyout = buyout,
		run_time = run_time, deposit = deposit,
	})
end

local function on_post_confirmed()
	local p = tremove(pending_posts, 1)
	if not p or not p.link then return end
	local item_id = info.parse_link(p.link)
	local itemstring = bc.bc_itemstring(p.link)
	if not item_id or item_id == 0 or not itemstring then return end
	bc.store_link(p.link)
	bc.db_add('postedAuctions', item_id, itemstring,
		bc.pack(p.count, p.min_bid, p.buyout, p.run_time, p.deposit, time(), '', '', '', ''))
end

local function on_post_failed()
	tremove(pending_posts, 1)
end

local function on_start_auction(min_bid, buyout, run_time, count, stack_number)
	local name = GetAuctionSellItemInfo()
	if not name or not count then return end
	local link, locked_count = find_locked_item()
	local minutes = run_time
	if minutes == 1 then minutes = 720
	elseif minutes == 2 then minutes = 1440
	elseif minutes == 3 then minutes = 2880 end
	local deposit = CalculateAuctionDeposit(run_time, count)
	last_multi = {link=link, name=name, count=count, min_bid=min_bid,
	              buyout=buyout, run_time=minutes, deposit=deposit}
	if stack_number and (stack_number > 1 or count > (locked_count or 0)) then
		-- Multipost: AUCTION_MULTISELL_UPDATE will fire for each posted stack.
	else
		add_pending_post(link, name, count, min_bid, buyout, minutes, deposit)
	end
end

local function add_pending_bid(name, count, bid, owner, is_buyout, is_high, time_left, link)
	tinsert(pending_bids, {
		name=name, count=count, bid=bid, owner=owner,
		is_buyout=is_buyout, is_high=is_high, time_left=time_left, link=link,
	})
end

local function on_bid_confirmed()
	local b = tremove(pending_bids, 1)
	if not b or not b.link then return end
	local item_id = info.parse_link(b.link)
	local itemstring = bc.bc_itemstring(b.link)
	if not item_id or item_id == 0 or not itemstring then return end
	bc.store_link(b.link)
	bc.db_add('postedBids', item_id, itemstring,
		bc.pack(b.count, b.bid, b.owner, b.is_buyout, b.time_left, time(), '', '', '', ''))
end

local function on_bid_failed()
	tremove(pending_bids, 1)
end

local function on_place_auction_bid(list_type, index, bid)
	local name, _, count, _, _, _, _, _, buyout, _, high_bidder, owner = GetAuctionItemInfo(list_type, index)
	local link = GetAuctionItemLink(list_type, index)
	local time_left = GetAuctionItemTimeLeft(list_type, index)
	if name and count and bid then
		add_pending_bid(name, count, bid, owner or '?', bid == buyout, high_bidder, time_left, link)
	end
end

local hooks_installed
local function install_hooks()
	if hooks_installed or not _G.StartAuction then return end
	hooksecurefunc('StartAuction', on_start_auction)
	hooksecurefunc('PlaceAuctionBid', on_place_auction_bid)
	hooks_installed = true
end

local function find_post_match(item_id, itemstring, predicate)
	local list = bc.db_list('postedAuctions', item_id, itemstring)
	for i, raw in ipairs(list) do
		local stack, bid_, _, run_time, deposit, posted_time = strsplit(';', raw)
		local entry = {
			stack = tonumber(stack) or 0,
			bid = tonumber(bid_) or 0,
			run_time = tonumber(run_time) or 0,
			deposit = tonumber(deposit) or 0,
			time = tonumber(posted_time) or 0,
		}
		if predicate(entry) then
			tremove(list, i)
			return entry
		end
	end
end

local function record_completed_auction(item_link, sale_money, deposit, fee, buyout, buyer, t)
	local item_id = info.parse_link(item_link)
	local itemstring = bc.bc_itemstring(item_link)
	if not item_id or item_id == 0 or not itemstring then return end
	local oldest = t - 208800
	local match = find_post_match(item_id, itemstring, function(p)
		return p.deposit == deposit and p.bid <= buyout and t > p.time and oldest < p.time
	end)
	local stack = match and match.stack or 1
	local original_bid = match and match.bid or buyout
	bc.db_add('completedAuctions', item_id, itemstring,
		bc.pack(stack, sale_money, deposit, fee, buyout, original_bid, buyer, t, '', 'A'))
end

local function record_failed_auction(item_link, stack, t)
	local item_id = info.parse_link(item_link)
	local itemstring = bc.bc_itemstring(item_link)
	if not item_id or item_id == 0 or not itemstring then return end
	local match = find_post_match(item_id, itemstring, function(p)
		return p.stack == stack and abs(t - p.time - p.run_time*60) < 21600
	end)
	local deposit = match and match.deposit or 0
	local original_bid = match and match.bid or 0
	bc.db_add('failedAuctions', item_id, itemstring,
		bc.pack(stack, '', deposit, '', '', original_bid, '', t, '', 'A'))
end

local function record_completed_buy(item_link, paid, buyout, seller, t, stack)
	local item_id = info.parse_link(item_link)
	local itemstring = bc.bc_itemstring(item_link)
	if not item_id or item_id == 0 or not itemstring then return end
	bc.db_add('completedBidsBuyouts', item_id, itemstring,
		bc.pack(stack or 1, paid, '', '', buyout, paid, seller, t, '', 'A'))
end

local function record_failed_bid(item_link, refund, t)
	local item_id = info.parse_link(item_link)
	local itemstring = bc.bc_itemstring(item_link)
	if not item_id or item_id == 0 or not itemstring then return end
	bc.db_add('failedBids', item_id, itemstring,
		bc.pack('', refund, '', '', '', '', '', t, '', 'A'))
end

local subj_sold      = AUCTION_SOLD_MAIL_SUBJECT:gsub('(.+)%%s', '%1')
local subj_won       = AUCTION_WON_MAIL_SUBJECT:gsub('(.+)%%s', '%1')
local subj_expired   = AUCTION_EXPIRED_MAIL_SUBJECT:gsub('(.+)%%s', '%1')
local subj_outbid    = AUCTION_OUTBID_MAIL_SUBJECT:gsub('(.+)%%s', '%1')
local subj_cancelled = AUCTION_REMOVED_MAIL_SUBJECT:gsub('(.+)%%s', '%1')

local processed = {}
local function key_of(sender, subject, money, days_left)
	return sender .. '|' .. subject .. '|' .. (money or 0) .. '|' .. (days_left or 0)
end

local function looks_like_ah(subject)
	return subject and (
		strfind(subject, subj_sold, 1, true) or
		strfind(subject, subj_won, 1, true) or
		strfind(subject, subj_expired, 1, true) or
		strfind(subject, subj_outbid, 1, true) or
		strfind(subject, subj_cancelled, 1, true))
end

local function find_link_for_name(name)
	if not _G.BeanCounterDBNames then return end
	for key, v in pairs(_G.BeanCounterDBNames) do
		local hex, n = strsplit(';', v)
		if n == name then
			local id, suf = strsplit(':', key)
			return '|'..hex..'|Hitem:'..id..':0:0:0:0:0:'..suf..':0:80|h['..n..']|h|r'
		end
	end
end

local function process_inbox()
	local n = GetInboxNumItems()
	for i = 1, n do
		local _, _, sender, subject, money, _, days_left = GetInboxHeaderInfo(i)
		if sender and looks_like_ah(subject) then
			local k = key_of(sender, subject, money, days_left)
			if not processed[k] then
				processed[k] = true
				local age_seconds = floor((30 - (days_left or 30)) * 86400)
				local t = time() - age_seconds
				local item_link = GetInboxItemLink(i, 1)
				local _, _, stack = GetInboxItem(i)
				if strfind(subject, subj_sold, 1, true) then
					local _, _, _, buyer, bid, buyout, deposit, fee = GetInboxInvoiceInfo(i)
					if buyer and bid and bid > 0 then
						local item_name = strsub(subject, strlen(subj_sold) + 1)
						local link = item_link or find_link_for_name(item_name)
						if link then record_completed_auction(link, bid, deposit or 0, fee or 0, buyout or bid, buyer, t) end
					end
				elseif strfind(subject, subj_won, 1, true) then
					local _, _, _, seller, bid, buyout = GetInboxInvoiceInfo(i)
					if item_link and seller and bid and bid > 0 then
						record_completed_buy(item_link, bid, buyout or bid, seller, t, stack or 1)
					end
				elseif strfind(subject, subj_expired, 1, true) then
					if item_link then record_failed_auction(item_link, stack or 1, t) end
				elseif strfind(subject, subj_outbid, 1, true) then
					if item_link and money then record_failed_bid(item_link, money, t) end
				elseif strfind(subject, subj_cancelled, 1, true) then
					if item_link then record_failed_auction(item_link, stack or 1, t) end
				end
			end
		end
	end
end

local frame = CreateFrame('Frame')
frame:RegisterEvent('ADDON_LOADED')
frame:RegisterEvent('PLAYER_LOGIN')
frame:RegisterEvent('CHAT_MSG_SYSTEM')
frame:RegisterEvent('UI_ERROR_MESSAGE')
frame:RegisterEvent('AUCTION_MULTISELL_UPDATE')
frame:RegisterEvent('MAIL_INBOX_UPDATE')
frame:RegisterEvent('MAIL_CLOSED')
frame:SetScript('OnEvent', function()
	local e, a1 = event, arg1
	if e == 'ADDON_LOADED' or e == 'PLAYER_LOGIN' then
		install_hooks()
	elseif e == 'CHAT_MSG_SYSTEM' then
		if a1 == ERR_AUCTION_STARTED and getn(pending_posts) > 0 then
			on_post_confirmed()
		elseif a1 == ERR_AUCTION_BID_PLACED and getn(pending_bids) > 0 then
			on_bid_confirmed()
		end
	elseif e == 'UI_ERROR_MESSAGE' then
		if a1 == ERR_NOT_ENOUGH_MONEY and getn(pending_posts) > 0 then
			on_post_failed()
		elseif a1 == ERR_AUCTION_BID_OWN
		    or a1 == ERR_AUCTION_HIGHER_BID
		    or a1 == ERR_ITEM_NOT_FOUND then
			if getn(pending_bids) > 0 then on_bid_failed() end
		end
	elseif e == 'AUCTION_MULTISELL_UPDATE' then
		if last_multi.link then
			add_pending_post(last_multi.link, last_multi.name, last_multi.count,
			                 last_multi.min_bid, last_multi.buyout, last_multi.run_time, last_multi.deposit)
		end
	elseif e == 'MAIL_INBOX_UPDATE' then
		process_inbox()
	elseif e == 'MAIL_CLOSED' then
		processed = {}
	end
end)
