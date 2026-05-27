module 'aux.core.slash'

include 'aux'

local cache = require 'aux.core.cache'

function LOAD2()
	tooltip_settings = character_data'tooltip'
end

_G.aux_ignore_owner = true
-- Per-item stack memory is the expected default; an earlier rev of this addon
-- defaulted it off, leaving aux_post_stack=false in some users' SavedVariables.
-- Force it on once via a marker so we don't fight users who later toggled off.
if not aux_post_stack_default_migrated then
	_G.aux_post_stack = true
	_G.aux_post_stack_default_migrated = true
end
if aux_purchase_summary == nil then _G.aux_purchase_summary = true end
if aux_undercut == nil then _G.aux_undercut = true end

-- DURATION_12, DURATION_24, DURATION_48 = 1, 2, 3 (matches tabs/post/core.lua)
local DURATION_NAMES = {[1]='12h', [2]='24h', [3]='48h'}
local DURATION_INPUTS = {['12']=1, ['24']=2, ['48']=3}

function status(enabled)
	return (enabled and color.green'on' or color.red'off')
end

_G.SLASH_AUX1 = '/aux'
function SlashCmdList.AUX(command)
	if not command then return end
	local arguments = tokenize(command)

    if arguments[1] == 'scale' and tonumber(arguments[2]) then
    	local scale = tonumber(arguments[2])
	    AuxFrame:SetScale(scale)
	    _G.aux_scale = scale
    elseif arguments[1] == 'ignore' and arguments[2] == 'owner' then
	    _G.aux_ignore_owner = not aux_ignore_owner
        print('ignore owner ' .. status(aux_ignore_owner))
    elseif arguments[1] == 'post' and arguments[2] == 'bid' then
	    _G.aux_post_bid = not aux_post_bid
	    print('post bid ' .. status(aux_post_bid))
    elseif arguments[1] == 'post' and arguments[2] == 'stack' then
	    _G.aux_post_stack = not aux_post_stack
	    print('post stack ' .. status(aux_post_stack))
    elseif arguments[1] == 'post' and arguments[2] == 'duration' and DURATION_INPUTS[arguments[3]] then
	    _G.aux_post_duration = DURATION_INPUTS[arguments[3]]
	    print('post duration ' .. color.blue(DURATION_NAMES[aux_post_duration]))
    elseif arguments[1] == 'uc' then
	    _G.aux_undercut = not aux_undercut
	    print('undercutting ' .. status(aux_undercut))
    elseif arguments[1] == 'purchase' and arguments[2] == 'summary' then
	    _G.aux_purchase_summary = not aux_purchase_summary
	    print('purchase summary ' .. status(aux_purchase_summary))
	    if not aux_purchase_summary then
	        local ps = require 'aux.gui.purchase_summary'
	        ps.hide()
	    end
    elseif arguments[1] == 'tooltip' and arguments[2] == 'value' then
	    tooltip_settings.value = not tooltip_settings.value
        print('tooltip value ' .. status(tooltip_settings.value))
    elseif arguments[1] == 'tooltip' and arguments[2] == 'daily' then
	    tooltip_settings.daily = not tooltip_settings.daily
        print('tooltip daily ' .. status(tooltip_settings.daily))
    elseif arguments[1] == 'tooltip' and arguments[2] == 'merchant' and arguments[3] == 'buy' then
	    tooltip_settings.merchant_buy = not tooltip_settings.merchant_buy
        print('tooltip merchant buy ' .. status(tooltip_settings.merchant_buy))
    elseif arguments[1] == 'tooltip' and arguments[2] == 'merchant' and arguments[3] == 'sell' then
	    tooltip_settings.merchant_sell = not tooltip_settings.merchant_sell
        print('tooltip merchant sell ' .. status(tooltip_settings.merchant_sell))
    elseif arguments[1] == 'tooltip' and arguments[2] == 'disenchant' and arguments[3] == 'value' then
	    tooltip_settings.disenchant_value = not tooltip_settings.disenchant_value
        print('tooltip disenchant value ' .. status(tooltip_settings.disenchant_value))
    elseif arguments[1] == 'tooltip' and arguments[2] == 'disenchant' and arguments[3] == 'distribution' then
	    tooltip_settings.disenchant_distribution = not tooltip_settings.disenchant_distribution
        print('tooltip disenchant distribution ' .. status(tooltip_settings.disenchant_distribution))
    elseif arguments[1] == 'clear' and arguments[2] == 'item' and arguments[3] == 'cache' then
	    _G.aux_items = {}
	    _G.aux_item_ids = {}
	    _G.aux_auctionable_items = {}
        print('Item cache cleared.')
    elseif arguments[1] == 'populate' and arguments[2] == 'wdb' then
	    cache.populate_wdb()
	else
		print('Usage:')
		print('- scale [' .. color.blue(aux_scale) .. ']')
		print('- ignore owner [' .. status(aux_ignore_owner) .. ']')
		print('- post bid [' .. status(aux_post_bid) .. ']')
		print('- post stack [' .. status(aux_post_stack) .. ']')
		print('- post duration 12|24|48 [' .. color.blue(DURATION_NAMES[aux_post_duration or 2]) .. ']')
		print('- uc [' .. status(aux_undercut) .. ']')
		print('- purchase summary [' .. status(aux_purchase_summary) .. ']')
		print('- tooltip value [' .. status(tooltip_settings.value) .. ']')
		print('- tooltip daily [' .. status(tooltip_settings.daily) .. ']')
		print('- tooltip merchant buy [' .. status(tooltip_settings.merchant_buy) .. ']')
		print('- tooltip merchant sell [' .. status(tooltip_settings.merchant_sell) .. ']')
		print('- tooltip disenchant value [' .. status(tooltip_settings.disenchant_value) .. ']')
		print('- tooltip disenchant distribution [' .. status(tooltip_settings.disenchant_distribution) .. ']')
		print('- clear item cache')
		print('- populate wdb')
    end
end