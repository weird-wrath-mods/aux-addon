module 'aux.tabs.beancounter'

include 'T'
include 'aux'

local info = require 'aux.util.info'
local money = require 'aux.util.money'
local bc = require 'aux.core.beancounter'

TAB 'BeanCounter'

local BUCKET_LABELS = {
	completedAuctions    = color.green'Sold',
	failedAuctions       = color.red'Expired',
	completedBidsBuyouts = color.blue'Bought',
	failedBids           = color.orange'Outbid',
}

current_filter = ''

local function entry_price(e)
	if e.bucket == 'completedAuctions' then
		return e.money - e.deposit, 'net'
	elseif e.bucket == 'failedAuctions' then
		return -e.deposit, 'fee'
	elseif e.bucket == 'completedBidsBuyouts' then
		return -(e.money > 0 and e.money or e.bid), 'paid'
	elseif e.bucket == 'failedBids' then
		return e.money, 'refund'
	end
	return 0, ''
end

function rebuild_rows()
	local rows = T
	if not bc.available() then
		listing:SetData(rows)
		return
	end
	local db = _G.BeanCounterDB[GetRealmName()][UnitName('player')]
	local needle = strlower(trim(current_filter or ''))
	local seen = T

	for _, bucket in ipairs(temp-A('completedAuctions', 'failedAuctions', 'completedBidsBuyouts', 'failedBids')) do
		if db[bucket] then
			for item_id in pairs(db[bucket]) do
				if not seen[item_id] then
					seen[item_id] = true
					local item_info = temp-info.item(item_id)
					local name = item_info and item_info.name or ('item:' .. item_id)
					if needle == '' or strfind(strlower(name), needle, 1, true) then
						for _, e in ipairs(bc.all_entries(item_id)) do
							local p = entry_price(e)
							local price_color = p >= 0 and color.green or color.red
							tinsert(rows, O(
								'cols', A(
									O('value', date('%Y-%m-%d', e.time)),
									O('value', BUCKET_LABELS[e.bucket] or e.bucket),
									O('value', name),
									O('value', tostring(e.stack)),
									O('value', price_color(money.to_string2(p))),
									O('value', e.buyer or '')
								),
								'entry', e,
								'item_id', item_id
							))
						end
					end
				end
			end
		end
	end

	table.sort(rows, function(a, b) return a.entry.time > b.entry.time end)
	listing:SetData(rows)
end

function OPEN()
	frame:Show()
	rebuild_rows()
end

function CLOSE()
	frame:Hide()
end

function set_filter(s)
	current_filter = s or ''
	rebuild_rows()
end
