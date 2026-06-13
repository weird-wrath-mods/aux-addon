module 'aux.tabs.search'

local filter_util = require 'aux.util.filter'
local gui = require 'aux.gui'

function LOAD2()
	recent_searches, favorite_searches = realm_data'recent_searches', realm_data'favorite_searches'
end

function update_search_listings()
	local favorite_search_rows = T
	for i = 1, getn(favorite_searches) do
		local search = favorite_searches[i]
		local name = strsub(search.prettified, 1, 250)
		local marker = search.auto_buy and color.red'X' or search.auto_bid and color.red'Y' or ''
		tinsert(favorite_search_rows, O(
			'cols', A(O('value', marker), O('value', name)),
			'search', search,
			'index', i
		))
	end
	favorite_searches_listing:SetData(favorite_search_rows)

	local recent_search_rows = T
	for i = 1, getn(recent_searches) do
		local search = recent_searches[i]
		local name = strsub(search.prettified, 1, 250)
		tinsert(recent_search_rows, O(
			'cols', A(O('value', name)),
			'search', search,
			'index', i
		))
	end
	recent_searches_listing:SetData(recent_search_rows)
end

function new_recent_search(filter_string, prettified)
	tinsert(recent_searches, 1, O(
		'filter_string', filter_string,
		'prettified', prettified
	))
	while getn(recent_searches) > 50 do
		tremove(recent_searches)
	end
	update_search_listings()
end

handlers = {
	OnClick = function(st, data, _, button)
		if not data then return end
		if button == 'LeftButton' and IsShiftKeyDown() then
			filter = data.search.filter_string
		elseif button == 'RightButton' and IsShiftKeyDown() then
			add_filter(data.search.filter_string)
		elseif button == 'LeftButton' then
			filter = data.search.filter_string
			execute()
		elseif button == 'RightButton' then
			local u = update_search_listings
			if st == recent_searches_listing then
				tinsert(favorite_searches, 1, data.search)
				u(d)
			elseif st == favorite_searches_listing then
				local auto_buy = data.search.auto_buy
				local auto_bid = data.search.auto_bid
				gui.menu(
					(auto_buy and 'Disable' or 'Enable') .. ' Auto Buy', function() if auto_buy then data.search.auto_buy = nil else enable_auto_buy(data.search) end u() end,
					(auto_bid and 'Disable' or 'Enable') .. ' Auto Bid', function() if auto_bid then data.search.auto_bid = nil else enable_auto_bid(data.search) end u() end,
					'Move Up', function() move_up(favorite_searches, data.index); u() end,
					'Move Down', function() move_down(favorite_searches, data.index); u() end,
					'Delete', function() tremove(favorite_searches, data.index); u() end
				)
			end
		end
	end,
	OnEnter = function(st, data, self)
		if not data then return end
		GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
		GameTooltip:AddLine(gsub(data.search.prettified, ';', '\n\n'), 255/255, 254/255, 250/255, true)
		GameTooltip:Show()
	end,
	OnLeave = function()
		GameTooltip:ClearLines()
		GameTooltip:Hide()
	end
}

function add_favorite(filter_string)
	local queries, error = filter_util.queries(filter_string)
	if queries then
		tinsert(favorite_searches, 1, O(
			'filter_string', filter_string,
			'prettified', join(map(queries, function(query) return query.prettified end), ';')
		))
		update_search_listings()
	else
		print('Invalid filter:', error)
	end
end

function get_auto_buy_validator()
	local validators = T
	for _, search in pairs(favorite_searches) do
		if search.auto_buy then
			local queries, error = filter_util.queries(search.filter_string)
			if queries then
				for _, query in pairs(queries) do tinsert(validators, query.validator) end
			else
				print('Invalid auto buy filter:', error)
			end
		end
	end
	return function(record)
		return any(validators, function(validator) return validator(record) end)
	end
end

function get_auto_bid_validator()
	local validators = T
	for _, search in pairs(favorite_searches) do
		if search.auto_bid then
			local queries, error = filter_util.queries(search.filter_string)
			if queries then
				for _, query in pairs(queries) do tinsert(validators, query.validator) end
			else
				print('Invalid auto bid filter:', error)
			end
		end
	end
	return function(record)
		return any(validators, function(validator) return validator(record) end)
	end
end

-- A multi-item filter (parts split on ';') is allowed: each part's validator is OR'd into the
-- auto-buy/bid test (see get_auto_buy_validator). The only constraint is per part: a Blizzard
-- filter must be exact, otherwise that part's validator matches everything on the page.
function nonexact_blizzard_part(filter_string)
	local parts = split(filter_string, ';')
	local queries = filter_util.queries(filter_string)
	for i = 1, getn(parts) do
		if queries[i] and size(queries[i].blizzard_query) > 0 and not filter_util.parse_filter_string(parts[i]).blizzard.exact then
			return parts[i]
		end
	end
end

function enable_auto_buy(search)
	local queries, error = filter_util.queries(search.filter_string)
	if not queries then
		print('Invalid filter:', error)
		return
	end
	local bad = nonexact_blizzard_part(search.filter_string)
	if bad then
		print('Error: Auto Buy needs exact items for Blizzard filters:', bad)
	else
		search.auto_buy = true
	end
end

function enable_auto_bid(search)
	local queries, error = filter_util.queries(search.filter_string)
	if not queries then
		print('Invalid filter:', error)
		return
	end
	local bad = nonexact_blizzard_part(search.filter_string)
	if bad then
		print('Error: Auto Bid needs exact items for Blizzard filters:', bad)
	else
		search.auto_bid = true
	end
end

function move_up(list, index)
	if list[index - 1] then
		list[index], list[index - 1] = list[index - 1], list[index]
	end
end

function move_down(list, index)
	if list[index + 1] then
		list[index], list[index + 1] = list[index + 1], list[index]
	end
end