module 'aux.core.post'

include 'T'
include 'aux'

local info = require 'aux.util.info'
local money = require 'aux.util.money'
local stack = require 'aux.core.stack'
local history = require 'aux.core.history'
local disenchant = require 'aux.core.disenchant'
local cache = require 'aux.core.cache'

local state

function process()
	if state.posted < state.count then

		local stacking_complete

		local send_signal, signal_received = signal()
		when(signal_received, function()
			local slot = signal_received()[1]
			if slot then
				return post_auction(slot, process)
			else
				return stop()
			end
		end)

		return stack.start(state.item_key, state.stack_size, send_signal)
	end

	return stop()
end

function post_auction(slot, k)
	local item_info = info.container_item(unpack(slot))
	if item_info.item_key == state.item_key and info.auctionable(item_info.tooltip, nil, true) and item_info.aux_quantity == state.stack_size then
        
		ClearCursor()
		ClickAuctionSellItemButton()
		ClearCursor()
		PickupContainerItem(unpack(slot))
		ClickAuctionSellItemButton()
		ClearCursor()

		local start_price = state.unit_start_price
		local buyout_price = state.unit_buyout_price

		-- Autopricing heuristic: triggered when start bid is 0. Uses history,
		-- vendor info, and disenchant value to derive a reasonable floor.
		-- Refuses to post if the data suggests vendoring or disenchanting beats
		-- the AH outcome.
		if start_price == 0 then
			local has_market = 0
			local has_buyout_floor = 0
			local missing_data = 0
			local vendor_sell = 0

			if buyout_price > 0 then
				has_buyout_floor = 1
				start_price = buyout_price
			end

			if history.market_value(state.item_key) then
				local m = max(1, history.market_value(state.item_key) - 1)
				buyout_price = max(buyout_price, m)
				has_market = 1
			end

			if history.value(state.item_key) then
				local v = history.value(state.item_key)
				if has_buyout_floor == 1 and has_market == 1 then
					buyout_price = max(buyout_price, 0.50 * v)
				elseif has_market == 1 then
					start_price = max(start_price, 0.80 * v)
				else
					buyout_price = max(buyout_price, 0.95 * v)
				end
			else
				missing_data = missing_data + 1
			end

			local m_sell, m_buy, m_limited = cache.merchant_info(item_info.item_id)
			if m_buy and not m_limited then
				start_price = max(start_price, m_buy * 1.1)
				buyout_price = max(buyout_price, m_buy * 1.15)
			else
				if m_sell then vendor_sell = m_sell end
				if vendor_sell > 0 then
					if has_market == 0 then
						start_price = max(start_price, vendor_sell * (1.35 + 3.65 * math.exp(-(1/4000) * vendor_sell)))
					else
						start_price = max(start_price, vendor_sell * 1.35)
					end
				else
					missing_data = missing_data + 1
				end
			end

			local de = disenchant.value(item_info.slot, item_info.quality, item_info.level, item_info.item_id)
			if de then
				start_price = max(start_price, 0.85 * de)
			end

			start_price = max(start_price, 0.91 * buyout_price)
			buyout_price = max(start_price, buyout_price)

			if de and buyout_price < 0.95 * de - 30 then
				print('autopricing recommends disenchanting!')
				return stop()
			end

			if has_market == 1 and vendor_sell > 0 then
				if history.value(state.item_key) < 1.35 * vendor_sell
					or history.market_value(state.item_key) < 1.35 * vendor_sell then
					print('autopricing recommends vendoring!')
					return stop()
				end
			end

			if start_price == 0 or (missing_data == 2 and has_buyout_floor == 0) then
				print('insufficient data for autopricing!')
				return stop()
			end

			print('bid_price: ' .. money.to_string(round(start_price), nil, true))
			print('buyout_price: ' .. money.to_string(round(buyout_price), nil, true))
		end

		StartAuction(max(1, round(start_price * item_info.aux_quantity)), round(buyout_price * item_info.aux_quantity), state.duration, state.stack_size, 1)

		local send_signal, signal_received = signal()
		when(signal_received, function()
			state.posted = state.posted + 1
			return k()
		end)

		local posted
		event_listener('CHAT_MSG_SYSTEM', function(kill)
			if arg1 == ERR_AUCTION_STARTED then
				send_signal()
				kill()
			end
		end)
	else
		return stop()
	end
end

function M.stop()
	if state then
		kill_thread(state.thread_id)

		local callback = state.callback
		local posted = state.posted

		state = nil

		if callback then
			callback(posted)
		end
	end
end

function M.start(item_key, stack_size, duration, unit_start_price, unit_buyout_price, count, callback)
	stop()
	state = {
		thread_id = thread(process),
		item_key = item_key,
		stack_size = stack_size,
		duration = duration,
		unit_start_price = unit_start_price,
		unit_buyout_price = unit_buyout_price,
		count = count,
		posted = 0,
		callback = callback,
	}
end
