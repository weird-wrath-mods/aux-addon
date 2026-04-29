module 'aux.tabs.post'

include 'T'
include 'aux'

local info = require 'aux.util.info'
local sort_util = require 'aux.util.sort'
local persistence = require 'aux.util.persistence'
local money = require 'aux.util.money'
local scan_util = require 'aux.util.scan'
local post = require 'aux.core.post'
local scan = require 'aux.core.scan'
local history = require 'aux.core.history'
local cache = require 'aux.core.cache'
local item_listing = require 'aux.gui.item_listing'
local al = require 'aux.gui.auction_listing'

TAB 'Post'

local DURATION_12, DURATION_24, DURATION_48 = 1, 2, 3

local settings_schema = {'tuple', '#', {duration='number'}, {start_price='number'}, {buyout_price='number'}, {hidden='boolean'}, {stack_size='number'}, {queued='boolean'}}

local scan_id, inventory_records, bid_records, buyout_records = 0, {}, {}, {}
local batch_posting, batch_scan_id = false, nil

function get_default_settings()
	return O('duration', DURATION_24, 'start_price', 0, 'buyout_price', 0, 'hidden', false, 'stack_size', 0, 'queued', false)
end

function LOAD2()
	data = faction_data'post'
end

function read_settings(item_key)
	item_key = item_key or selected_item.key
	return data[item_key] and persistence.read(settings_schema, data[item_key]) or default_settings
end
function write_settings(settings, item_key)
	item_key = item_key or selected_item.key
	data[item_key] = persistence.write(settings_schema, settings)
end

do
	local bid_selections, buyout_selections = {}, {}
	function get_bid_selection()
		return bid_selections[selected_item.key]
	end
	function set_bid_selection(record)
		bid_selections[selected_item.key] = record
	end
	function get_buyout_selection()
		return buyout_selections[selected_item.key]
	end
	function set_buyout_selection(record)
		buyout_selections[selected_item.key] = record
	end
end

function refresh_button_click()
	scan.abort(scan_id)
	refresh_entries()
	refresh = true
end

do
	local item
	function get_selected_item() return item end
	function set_selected_item(v) item = v end
end

do
	local c = 0
	function get_refresh() return c end
	function set_refresh(v) c = v end
end

function OPEN()
    frame:Show()
    update_inventory_records()
    refresh = true
end

function CLOSE()
    selected_item = nil
    frame:Hide()
end

function USE_ITEM(item_id, suffix_id)
	select_item(item_id .. ':' .. suffix_id)
end

function get_unit_start_price()
	return selected_item and read_settings().start_price or 0
end

function set_unit_start_price(amount)
	local settings = read_settings()
	settings.start_price = amount
	write_settings(settings)
end

function get_unit_buyout_price()
	return selected_item and read_settings().buyout_price or 0
end

function set_unit_buyout_price(amount)
	local settings = read_settings()
	settings.buyout_price = amount
	write_settings(settings)
end

function update_inventory_listing()
	local records = values(filter(copy(inventory_records), function(record)
		local settings = read_settings(record.key)
		return record.aux_quantity > 0 and (not settings.hidden or show_hidden_checkbox:GetChecked())
	end))
	for _, record in pairs(records) do
		record.queued = read_settings(record.key).queued
	end
	sort(records, function(a, b) return a.name < b.name end)
	item_listing.populate(inventory_listing, records)
end

function update_auction_listing(listing, records, reference)
	local rows = T
	if selected_item then
		local historical_value = history.value(selected_item.key)
		local stack_size = stack_size_slider:GetValue()
		for _, record in pairs(records[selected_item.key] or empty) do
			local price_color = undercut(record, stack_size_slider:GetValue(), listing == 'bid') < reference and color.red
			local price = record.unit_price * (listing == 'bid' and record.stack_size / stack_size_slider:GetValue() or 1)
			tinsert(rows, O(
				'cols', A(
				O('value', record.own and color.green(record.count) or record.count),
				O('value', al.time_left(record.duration)),
				O('value', record.stack_size == stack_size and color.green(record.stack_size) or record.stack_size),
				O('value', money.to_string(price, true, nil, price_color)),
				O('value', historical_value and al.percentage_historical(round(price / historical_value * 100)) or '---')
			),
				'record', record
			))
		end
		if historical_value then
			tinsert(rows, O(
				'cols', A(
				O('value', '---'),
				O('value', '---'),
				O('value', '---'),
				O('value', money.to_string(historical_value, true, nil, color.green)),
				O('value', historical_value and al.percentage_historical(100) or '---')
			),
				'record', O('historical_value', true, 'stack_size', stack_size, 'unit_price', historical_value, 'own', true)
			))
		end
		sort(rows, function(a, b)
			return sort_util.multi_lt(
				a.record.unit_price * (listing == 'bid' and a.record.stack_size or 1),
				b.record.unit_price * (listing == 'bid' and b.record.stack_size or 1),

				a.record.historical_value and 1 or 0,
				b.record.historical_value and 1 or 0,

				b.record.own and 0 or 1,
				a.record.own and 0 or 1,

				a.record.stack_size,
				b.record.stack_size,

				a.record.duration,
				b.record.duration
			)
		end)
	end
	if listing == 'bid' then
		bid_listing:SetData(rows)
	elseif listing == 'buyout' then
		buyout_listing:SetData(rows)
	end
end

function update_auction_listings()
	update_auction_listing('bid', bid_records, unit_start_price)
	update_auction_listing('buyout', buyout_records, unit_buyout_price)
end

function M.select_item(item_key)
    for _, inventory_record in pairs(filter(copy(inventory_records), function(record) return record.aux_quantity > 0 end)) do
        if inventory_record.key == item_key then
            update_item(inventory_record)
            return
        end
    end
end

function price_update()
    if selected_item then
        local historical_value = history.value(selected_item.key)
        if bid_selection or buyout_selection then
	        unit_start_price = undercut(bid_selection or buyout_selection, stack_size_slider:GetValue(), bid_selection)
	        unit_start_price_input:SetText(money.to_string(unit_start_price, true, nil, nil, true))
        end
        if buyout_selection then
	        unit_buyout_price = undercut(buyout_selection, stack_size_slider:GetValue())
	        unit_buyout_price_input:SetText(money.to_string(unit_buyout_price, true, nil, nil, true))
        end
        start_price_percentage:SetText(historical_value and al.percentage_historical(round(unit_start_price / historical_value * 100)) or '---')
        buyout_price_percentage:SetText(historical_value and al.percentage_historical(round(unit_buyout_price / historical_value * 100)) or '---')
    end
end

function post_auctions()
	if selected_item then
        local unit_start_price = unit_start_price
        local unit_buyout_price = unit_buyout_price
        local stack_size = stack_size_slider:GetValue()
        local stack_count
        stack_count = stack_count_slider:GetValue()
        local duration = UIDropDownMenu_GetSelectedValue(duration_dropdown)
		local key = selected_item.key

        -- local duration_code
		-- if duration == DURATION_2 then
            -- duration_code = 2
		-- elseif duration == DURATION_8 or duration == DURATION_12 then
            -- duration_code = 3
		-- elseif duration == DURATION_24 or duration == DURATION_48 then
            -- duration_code = 4
		-- end

		post.start(
			key,
			stack_size,
			duration,
            unit_start_price,
            unit_buyout_price,
			stack_count,
			function(posted)
				for i = 1, posted do
                    record_auction(key, stack_size, unit_start_price * stack_size, unit_buyout_price, duration + 1, UnitName'player')
                end
                update_inventory_records()
				local same
                for _, record in pairs(inventory_records) do
                    if record.key == key then
	                    same = record
	                    break
                    end
                end
                if same then
	                update_item(same)
                else
                    selected_item = nil
                end
                refresh = true
			end
		)
	end
end

function M.post_auctions_bind()
	post_auctions()
end

function post_all_click()
	if batch_posting then
		stop_batch()
	else
		post_all_queued()
	end
end

function stop_batch()
	if batch_posting then
		batch_posting = false
		if batch_scan_id then
			scan.abort(batch_scan_id)
			batch_scan_id = nil
		end
		post.stop()
		post_all_button:SetText('Post All')
		status_bar:update_status(1, 1)
		status_bar:set_text('Batch posting cancelled')
		update_inventory_records()
		refresh = true
	end
end

function post_all_queued()
	local queue = T
	for _, record in pairs(inventory_records) do
		if record.aux_quantity > 0 and read_settings(record.key).queued then
			local s = read_settings(record.key)
			local ss = s.stack_size and s.stack_size > 0 and s.stack_size or 1
			tinsert(queue, O('key', record.key, 'name', record.name, 'item_id', record.item_id, 'total_value', (history.value(record.key) or 0) * ss))
		end
	end
	sort(queue, function(a, b) return a.total_value > b.total_value end)

	if getn(queue) == 0 then
		print('No items queued for posting')
		return
	end

	batch_posting = true
	post_all_button:SetText('Stop')
	post_button:Disable()

	local queue_index = 0

	local function process_next()
		queue_index = queue_index + 1

		if queue_index > getn(queue) or not batch_posting then
			batch_posting = false
			post_all_button:SetText('Post All')
			status_bar:update_status(1, 1)
			status_bar:set_text('Batch posting complete')
			update_inventory_records()
			refresh = true
			return
		end

		local item_key = queue[queue_index].key
		local item_name = queue[queue_index].name
		local item_id = queue[queue_index].item_id

		local record
		for _, r in pairs(inventory_records) do
			if r.key == item_key and r.aux_quantity > 0 then
				record = r
				break
			end
		end

		if not record then
			print(format('Skipping %s: no longer in inventory', item_name))
			return process_next()
		end

		status_bar:update_status((queue_index - 1) / getn(queue), 0)
		status_bar:set_text(format('Scanning %d/%d: %s', queue_index, getn(queue), item_name))

		local item_buyout_records = T
		local query = scan_util.item_query(item_id)

		batch_scan_id = scan.start{
			type = 'list',
			ignore_owner = true,
			queries = A(query),
			on_page_loaded = function(page, total_pages)
				status_bar:update_status((queue_index - 1) / getn(queue), 0)
				status_bar:set_text(format('Scanning %d/%d: %s (%d/%d)', queue_index, getn(queue), item_name, page, total_pages))
			end,
			on_auction = function(auction_record)
				if auction_record.item_key == item_key and auction_record.unit_buyout_price > 0 then
					tinsert(item_buyout_records, O(
						'unit_price', auction_record.unit_buyout_price,
						'own', cache.is_player(auction_record.owner)
					))
				end
			end,
			on_abort = function()
				if batch_posting then stop_batch() end
			end,
			on_complete = function()
				batch_scan_id = nil
				if not batch_posting then return end

				local settings = read_settings(item_key)
				local historical_value = history.value(item_key)
				if not historical_value then
					print(format('Skipping %s: no historical value', item_name))
					return process_next()
				end

				sort(item_buyout_records, function(a, b) return a.unit_price < b.unit_price end)

				local target
				for _, rec in pairs(item_buyout_records) do
					if rec.unit_price >= historical_value then
						target = rec
						break
					end
				end

				local unit_price
				if target and not target.own then
					unit_price = max(target.unit_price - 1, historical_value)
				else
					unit_price = historical_value
				end

				local stack_size = settings.stack_size and settings.stack_size > 0 and settings.stack_size or 1
				if record.max_stack and not record.max_charges and stack_size > record.max_stack then
					stack_size = record.max_stack
				end

				local available
				if record.max_charges then
					available = record.availability[stack_size] or 0
				else
					available = record.availability[0] or 0
				end

				local full_stacks, remainder
				if record.max_charges then
					full_stacks = available
					remainder = 0
				else
					full_stacks = floor(available / stack_size)
					remainder = mod(available, stack_size)
				end

				if full_stacks == 0 and remainder == 0 then
					print(format('Skipping %s: nothing to post at stack size %d', item_name, stack_size))
					return process_next()
				end

				local duration = settings.duration

				status_bar:set_text(format('Posting %d/%d: %s', queue_index, getn(queue), item_name))

				local function post_remainder()
					if not batch_posting then return end
					if remainder > 0 then
						post.start(item_key, remainder, duration, unit_price, unit_price, 1, function(posted)
							if not frame:IsShown() then return end
							for i = 1, posted do
								record_auction(item_key, remainder, unit_price * remainder, unit_price, duration + 1, UnitName'player')
							end
							update_inventory_records()
							refresh = true
							process_next()
						end)
					else
						process_next()
					end
				end

				if full_stacks > 0 then
					post.start(item_key, stack_size, duration, unit_price, unit_price, full_stacks, function(posted)
						if not frame:IsShown() then return end
						for i = 1, posted do
							record_auction(item_key, stack_size, unit_price * stack_size, unit_price, duration + 1, UnitName'player')
						end
						update_inventory_records()
						refresh = true
						post_remainder()
					end)
				else
					post_remainder()
				end
			end,
		}
	end

	process_next()
end

function validate_parameters()
    if batch_posting then
        post_button:Disable()
        return
    end
    if not selected_item then
        post_button:Disable()
        return
    end
    if unit_buyout_price > 0 and unit_start_price > unit_buyout_price then
        post_button:Disable()
        return
    end
    if unit_start_price == 0 then
        post_button:Enable()
        return
    end
    if stack_count_slider:GetValue() == 0 then
        post_button:Disable()
        return
    end
    post_button:Enable()
end

function update_item_configuration()
    if not selected_item then
        refresh_button:Disable()

        item.texture:SetTexture(nil)
        item.count:SetText()
        item.name:SetTextColor(color.label.enabled())
        item.name:SetText('No item selected')

        unit_start_price_input:Hide()
        unit_buyout_price_input:Hide()
        stack_size_slider:Hide()
        stack_count_slider:Hide()
        deposit:Hide()
        duration_dropdown:Hide()
        hide_checkbox:Hide()
        queue_checkbox:Hide()
    else
        unit_start_price_input:Show()
        unit_buyout_price_input:Show()
        stack_size_slider:Show()
        stack_count_slider:Show()
        deposit:Show()
        duration_dropdown:Show()
        hide_checkbox:Show()
        queue_checkbox:Show()

        item.texture:SetTexture(selected_item.texture)
        item.name:SetText('[' .. selected_item.name .. ']')
        do
            local color = ITEM_QUALITY_COLORS[selected_item.quality]
            item.name:SetTextColor(color.r, color.g, color.b)
        end
        if selected_item.aux_quantity > 1 then
            item.count:SetText(selected_item.aux_quantity)
        else
            item.count:SetText()
        end

        stack_size_slider.editbox:SetNumber(stack_size_slider:GetValue())
        stack_count_slider.editbox:SetNumber(stack_count_slider:GetValue())

        local deposit_factor = UnitFactionGroup'npc' and 0.05 or 0.25
        local duration_value = UIDropDownMenu_GetSelectedValue(duration_dropdown)
        local duration_factor = duration_value and (duration_value / 120) or nil
        local stack_size = selected_item.max_charges and 1 or stack_size_slider:GetValue()
        local stack_count = stack_count_slider:GetValue()

        -- Calcul sécurisé du dépôt avec minimum 1 silver par stack
        local amount = 0
        if selected_item.unit_vendor_price and duration_factor then
            amount = floor(selected_item.unit_vendor_price * deposit_factor * stack_size) * stack_count * duration_factor
            local min_deposit = 100 * stack_count -- 1 silver = 100 copper
            if amount < min_deposit then
                amount = min_deposit
            end
        else
            amount = 100 * stack_count -- dépôt minimum si données manquantes
        end

        deposit:SetText('Deposit: ' .. money.to_string(amount, nil, nil, color.text.enabled))

        refresh_button:Enable()
    end
end


function undercut(record, stack_size, stack)
    local price = ceil(record.unit_price * (stack and record.stack_size or stack_size))
    if not record.own then
	    price = price - 1
    end
    return price / stack_size
end

function quantity_update(maximize_count)
    if selected_item then
        local max_stack_count = selected_item.max_charges and selected_item.availability[stack_size_slider:GetValue()] or floor(selected_item.availability[0] / stack_size_slider:GetValue())
        stack_count_slider:SetMinMaxValues(1, max_stack_count)
        if maximize_count then
            stack_count_slider:SetValue(max_stack_count)
        end
    end
    refresh = true
end

function unit_vendor_price(item_key)
    for slot in info.inventory do
	    temp(slot)
        local item_info = temp-info.container_item(unpack(slot))
        if item_info and item_info.item_key == item_key then
            if info.auctionable(item_info.tooltip, nil, true) and not item_info.lootable then
                ClearCursor()
                PickupContainerItem(unpack(slot))
                ClickAuctionSellItemButton()
                local auction_sell_item = temp-info.auction_sell_item()
                ClearCursor()
                ClickAuctionSellItemButton()
                ClearCursor()
                if auction_sell_item then
                    return auction_sell_item.vendor_price / auction_sell_item.count
                end
            end
        end
    end
end

function update_item(item)
	CloseDropDownMenus()

    local settings = read_settings(item.key)

    item.unit_vendor_price = unit_vendor_price(item.key)
    if not item.unit_vendor_price then
        settings.hidden = true
        write_settings(settings, item.key)
        refresh = true
        return
    end

    scan.abort(scan_id)

    selected_item = item

    UIDropDownMenu_Initialize(duration_dropdown, initialize_duration_dropdown)
    UIDropDownMenu_SetSelectedValue(duration_dropdown, settings.duration)

    hide_checkbox:SetChecked(settings.hidden)
    queue_checkbox:SetChecked(settings.queued)

    local max_size
    if selected_item.max_charges then
	    for i = selected_item.max_charges, 1, -1 do
			if selected_item.availability[i] > 0 then
				stack_size_slider:SetMinMaxValues(1, i)
				max_size = i
				break
			end
	    end
    else
	    max_size = min(selected_item.max_stack, selected_item.aux_quantity)
	    stack_size_slider:SetMinMaxValues(1, max_size)
    end
    if aux_post_stack and settings.stack_size and settings.stack_size > 0 and max_size and settings.stack_size <= max_size then
        stack_size_slider:SetValue(settings.stack_size)
    else
        stack_size_slider:SetValue(huge)
    end
    quantity_update(true)

    unit_start_price_input:SetText(money.to_string(settings.start_price, true, nil, nil, true))
    unit_buyout_price_input:SetText(money.to_string(settings.buyout_price, true, nil, nil, true))

    if not bid_records[selected_item.key] then
        refresh_entries()
    end

    write_settings(settings, item.key)

    refresh = true
end

function update_inventory_records()
    local auctionable_map = temp-T
    for slot in info.inventory do
	    temp(slot)
	    local item_info = temp-info.container_item(unpack(slot))
        if item_info then
            local charge_class = item_info.charges or 0
            if info.auctionable(item_info.tooltip, nil, true) and not item_info.lootable then
                if not auctionable_map[item_info.item_key] then
                    local availability = T
                    for i = 0, 10 do
                        availability[i] = 0
                    end
                    availability[charge_class] = item_info.count
                    auctionable_map[item_info.item_key] = O(
	                    'item_id', item_info.item_id,
	                    'suffix_id', item_info.suffix_id,
	                    'key', item_info.item_key,
	                    'itemstring', item_info.itemstring,
	                    'name', item_info.name,
	                    'texture', item_info.texture,
	                    'quality', item_info.quality,
	                    'aux_quantity', item_info.charges or item_info.count,
	                    'max_stack', item_info.max_stack,
	                    'max_charges', item_info.max_charges,
	                    'availability', availability
                    )
                else
                    local auctionable = auctionable_map[item_info.item_key]
                    auctionable.availability[charge_class] = (auctionable.availability[charge_class] or 0) + item_info.count
                    auctionable.aux_quantity = auctionable.aux_quantity + (item_info.charges or item_info.count)
                end
            end
        end
    end
    release(inventory_records)
    inventory_records = values(auctionable_map)
    refresh = true
end

function refresh_entries()
	if selected_item then
        local item_key = selected_item.key
		bid_selection, buyout_selection = nil, nil
        bid_records[item_key], buyout_records[item_key] = nil, nil
        local query = scan_util.item_query(selected_item.item_id)
        status_bar:update_status(0, 0)
        status_bar:set_text('Scanning auctions...')

		scan_id = scan.start{
            type = 'list',
            ignore_owner = true,
			queries = A(query),
			on_page_loaded = function(page, total_pages)
                status_bar:update_status(page / total_pages, 0) -- TODO
                status_bar:set_text(format('Scanning Page %d / %d', page, total_pages))
			end,
			on_auction = function(auction_record)
				if auction_record.item_key == item_key then
                    record_auction(
                        auction_record.item_key,
                        auction_record.aux_quantity,
                        auction_record.unit_blizzard_bid,
                        auction_record.unit_buyout_price,
                        auction_record.duration,
                        auction_record.owner
                    )
				end
			end,
			on_abort = function()
				bid_records[item_key], buyout_records[item_key] = nil, nil
                status_bar:update_status(1, 1)
                status_bar:set_text('Scan aborted')
			end,
			on_complete = function()
				bid_records[item_key] = bid_records[item_key] or T
				buyout_records[item_key] = buyout_records[item_key] or T
                refresh = true
                status_bar:update_status(1, 1)
                status_bar:set_text('Scan complete')
            end,
		}
	end
end

function record_auction(key, aux_quantity, unit_blizzard_bid, unit_buyout_price, duration, owner)
    bid_records[key] = bid_records[key] or T
    do
	    local entry
	    for _, record in pairs(bid_records[key]) do
	        if unit_blizzard_bid == record.unit_price and aux_quantity == record.stack_size and duration == record.duration and cache.is_player(owner) == record.own then
	            entry = record
	        end
	    end
	    if not entry then
	        entry = O('stack_size', aux_quantity, 'unit_price', unit_blizzard_bid, 'duration', duration, 'own', cache.is_player(owner), 'count', 0)
	        tinsert(bid_records[key], entry)
	    end
	    entry.count = entry.count + 1
    end
    buyout_records[key] = buyout_records[key] or T
    if unit_buyout_price == 0 then return end
    do
	    local entry
	    for _, record in pairs(buyout_records[key]) do
		    if unit_buyout_price == record.unit_price and aux_quantity == record.stack_size and duration == record.duration and cache.is_player(owner) == record.own then
			    entry = record
		    end
	    end
	    if not entry then
		    entry = O('stack_size', aux_quantity, 'unit_price', unit_buyout_price, 'duration', duration, 'own', cache.is_player(owner), 'count', 0)
		    tinsert(buyout_records[key], entry)
	    end
	    entry.count = entry.count + 1
    end
end

function on_update()
    if refresh then
        refresh = false
        price_update()
        update_item_configuration()
        update_inventory_listing()
        update_auction_listings()
    end
    validate_parameters()
end

function initialize_duration_dropdown()
    local function on_click()
        UIDropDownMenu_SetSelectedValue(duration_dropdown, this.value)
        local settings = read_settings()
        settings.duration = this.value
        write_settings(settings)
        refresh = true
    end
    UIDropDownMenu_AddButton{
	    text = '12 Hours',
	    value = DURATION_12,
	    func = on_click,
    }
    UIDropDownMenu_AddButton{
	    text = '24 Hours',
	    value = DURATION_24,
	    func = on_click,
    }
    UIDropDownMenu_AddButton{
	    text = '48 Hours',
	    value = DURATION_48,
	    func = on_click,
    }
end
