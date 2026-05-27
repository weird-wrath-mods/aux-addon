module 'aux.core.disenchant'

include 'T'
include 'aux'

local history = require 'aux.core.history'

local UNCOMMON, RARE, EPIC = 2, 3, 4

-- Disenchant brackets and yields are ported verbatim from the ChromieCraft
-- server data (item_template.DisenchantID + disenchant_loot_template). The
-- server keys disenchant results off ITEM LEVEL, not required level, so every
-- caller must pass item level as `level`. aux already stores GetItemInfo's item
-- level as auction_record.level / item_info.level, so the internal callers are
-- correct as-is.
--
-- Uncommon armor and weapons use separate DisenchantIDs (different dust/essence
-- ratios); rare and epic only ever yield shards/crystals, so their brackets are
-- shared across both classes.

local ARMOR = S(
	'INVTYPE_HEAD',
	'INVTYPE_NECK',
	'INVTYPE_SHOULDER',
	'INVTYPE_BODY',
	'INVTYPE_CHEST',
	'INVTYPE_ROBE',
	'INVTYPE_WAIST',
	'INVTYPE_LEGS',
	'INVTYPE_FEET',
	'INVTYPE_WRIST',
	'INVTYPE_HAND',
	'INVTYPE_FINGER',
	'INVTYPE_TRINKET',
	'INVTYPE_CLOAK'
)

-- Note: the server disenchants held-in-off-hand, thrown and relics on the
-- weapon DisenchantID series, unlike a naive armor/weapon split.
local WEAPON = S(
	'INVTYPE_2HWEAPON',
	'INVTYPE_WEAPONMAINHAND',
	'INVTYPE_WEAPON',
	'INVTYPE_WEAPONOFFHAND',
	'INVTYPE_SHIELD',
	'INVTYPE_RANGED',
	'INVTYPE_RANGEDRIGHT',
	'INVTYPE_HOLDABLE',
	'INVTYPE_THROWN',
	'INVTYPE_RELIC'
)

-- disenchant_loot_template, one entry per DisenchantID. Each event is
-- {item_id, min_quantity, max_quantity, probability}. Within a DisenchantID
-- exactly one event fires (group loot), so probabilities sum to 1.
local DE_LOOT = {
	-- uncommon armor (dust-weighted)
	[1]  = {{10940,1,2,.8}, {10938,1,2,.2}},
	[2]  = {{10940,2,3,.75}, {10939,1,2,.2}, {10978,1,1,.05}},
	[3]  = {{10940,4,6,.75}, {10998,1,2,.15}, {10978,1,1,.1}},
	[4]  = {{11083,1,2,.75}, {11082,1,2,.2}, {11084,1,1,.05}},
	[5]  = {{11083,2,5,.75}, {11134,1,2,.2}, {11138,1,1,.05}},
	[6]  = {{11137,1,2,.75}, {11135,1,2,.2}, {11139,1,1,.05}},
	[7]  = {{11137,2,5,.75}, {11174,1,2,.2}, {11177,1,1,.05}},
	[8]  = {{11176,1,2,.75}, {11175,1,2,.2}, {11178,1,1,.05}},
	[9]  = {{11176,2,5,.75}, {16202,1,2,.2}, {14343,1,1,.05}},
	[10] = {{16204,1,2,.75}, {16203,1,2,.2}, {14344,1,1,.05}},
	[11] = {{16204,2,5,.75}, {16203,2,3,.2}, {14344,1,1,.05}},
	[12] = {{22445,1,3,.75}, {22447,1,3,.22}, {22448,1,1,.03}},
	[13] = {{22445,2,3,.75}, {22447,2,3,.22}, {22448,1,1,.03}},
	[14] = {{22445,2,5,.75}, {22446,1,2,.22}, {22449,1,1,.03}},
	[15] = {{34054,1,3,.75}, {34056,1,2,.22}, {34053,1,1,.03}},
	[16] = {{34054,4,7,.75}, {34055,1,2,.22}, {34052,1,1,.03}},
	-- uncommon weapon (essence-weighted)
	[21] = {{10938,1,2,.8}, {10940,1,2,.2}},
	[22] = {{10939,1,2,.75}, {10940,2,3,.2}, {10978,1,1,.05}},
	[23] = {{10998,1,2,.75}, {10940,4,6,.15}, {10978,1,1,.1}},
	[24] = {{11082,1,2,.75}, {11083,1,2,.2}, {11084,1,1,.05}},
	[25] = {{11134,1,2,.75}, {11083,2,5,.2}, {11138,1,1,.05}},
	[26] = {{11135,1,2,.75}, {11137,1,2,.2}, {11139,1,1,.05}},
	[27] = {{11174,1,2,.75}, {11137,2,5,.2}, {11177,1,1,.05}},
	[28] = {{11175,1,2,.75}, {11176,1,2,.2}, {11178,1,1,.05}},
	[29] = {{16202,1,2,.75}, {11176,2,5,.22}, {14343,1,1,.03}},
	[30] = {{16203,1,2,.75}, {16204,1,2,.22}, {14344,1,1,.03}},
	[31] = {{16203,2,3,.75}, {16204,2,5,.22}, {14344,1,1,.03}},
	[32] = {{22447,2,3,.75}, {22445,2,3,.22}, {22448,1,1,.03}},
	[33] = {{22446,1,2,.75}, {22445,2,5,.22}, {22449,1,1,.03}},
	[34] = {{34056,1,2,.75}, {34054,1,3,.22}, {34053,1,1,.03}},
	[35] = {{34055,1,2,.75}, {34054,4,7,.22}, {34052,1,1,.03}},
	-- rare (shared armor/weapon)
	[41] = {{10978,1,1,1}},
	[42] = {{11084,1,1,1}},
	[43] = {{11138,1,1,1}},
	[44] = {{11139,1,1,1}},
	[45] = {{11177,1,1,1}},
	[46] = {{11178,1,1,1}},
	[47] = {{14343,1,1,1}},
	[48] = {{14344,1,1,.995}, {20725,1,1,.005}},
	[49] = {{14344,1,1,.995}, {20725,1,1,.005}},
	[50] = {{22448,1,1,.995}, {20725,1,1,.005}},
	[51] = {{22448,1,1,.995}, {20725,1,1,.005}},
	[52] = {{22449,1,1,.995}, {22450,1,1,.005}},
	[53] = {{34053,1,1,.995}, {34057,1,1,.005}},
	[54] = {{34052,1,1,.995}, {34057,1,1,.005}},
	-- epic (shared armor/weapon)
	[61] = {{11177,2,4,1}},
	[62] = {{11178,2,4,1}},
	[63] = {{14343,2,4,1}},
	[64] = {{20725,1,1,1}},
	[65] = {{20725,1,2,1}},
	[66] = {{22450,1,2,1}},
	[67] = {{22450,1,1,1}},
	[68] = {{34057,1,1,1}},
	[69] = {{34057,1,2,1}},
}

-- Item level -> DisenchantID, matching the server's ItemDisenchantLoot brackets.
local function de_id(quality, weapon, lvl)
	if quality == UNCOMMON then
		if weapon then
			if     lvl <= 15  then return 21
			elseif lvl <= 20  then return 22
			elseif lvl <= 25  then return 23
			elseif lvl <= 30  then return 24
			elseif lvl <= 35  then return 25
			elseif lvl <= 40  then return 26
			elseif lvl <= 45  then return 27
			elseif lvl <= 50  then return 28
			elseif lvl <= 55  then return 29
			elseif lvl <= 60  then return 30
			elseif lvl <= 65  then return 31
			elseif lvl <= 99  then return 32
			elseif lvl <= 120 then return 33
			elseif lvl <= 150 then return 34
			else                   return 35 end
		else
			if     lvl <= 15  then return 1
			elseif lvl <= 20  then return 2
			elseif lvl <= 25  then return 3
			elseif lvl <= 30  then return 4
			elseif lvl <= 35  then return 5
			elseif lvl <= 40  then return 6
			elseif lvl <= 45  then return 7
			elseif lvl <= 50  then return 8
			elseif lvl <= 55  then return 9
			elseif lvl <= 60  then return 10
			elseif lvl <= 65  then return 11
			elseif lvl <= 80  then return 12
			elseif lvl <= 99  then return 13
			elseif lvl <= 120 then return 14
			elseif lvl <= 151 then return 15
			else                   return 16 end
		end
	elseif quality == RARE then
		if     lvl <= 25  then return 41
		elseif lvl <= 30  then return 42
		elseif lvl <= 35  then return 43
		elseif lvl <= 40  then return 44
		elseif lvl <= 45  then return 45
		elseif lvl <= 50  then return 46
		elseif lvl <= 55  then return 47
		elseif lvl <= 65  then return 48
		elseif lvl <= 70  then return 49
		elseif lvl <= 99  then return 50
		elseif lvl <= 115 then return 52
		elseif lvl <= 163 then return 53
		else                   return 54 end
	elseif quality == EPIC then
		-- Abyss-tier (lvl >= 165) mixes DEID 68 (1 Abyss) and 69 (1-2 Abyss) by
		-- raid tier, which item level can only approximate; the 210-229 band is
		-- predominantly 69, the rest 68.
		if     lvl <= 45  then return 61
		elseif lvl <= 50  then return 62
		elseif lvl <= 55  then return 63
		elseif lvl <= 60  then return 64
		elseif lvl <= 92  then return 65
		elseif lvl <= 100 then return 66
		elseif lvl <= 164 then return 67
		elseif lvl <= 209 then return 68
		elseif lvl <= 229 then return 69
		else                   return 68 end
	end
end

function M.value(slot, quality, level, item_id)
    local expectation
    for _, event in pairs(distribution(slot, quality, level, item_id)) do
        local value = history.value(event.item_id .. ':' .. 0)
        if not value then
            return
        end
        local market_value = history.market_value(event.item_id .. ':' .. 0)
        if market_value then
            value = min(value, market_value)
        end
        expectation = (expectation or 0) + event.probability * (event.min_quantity + event.max_quantity) / 2 * value
    end
    return expectation
end

function M.distribution(slot, quality, level, item_id)
    local weapon
    if ARMOR[slot] then
        weapon = false
    elseif WEAPON[slot] then
        weapon = true
    else
        return {}
    end

    if not level or level == 0 then
        return {}
    end

    -- Items that ignore the general DE rules: not disenchantable.
    if item_id == 20408 or item_id == 20407 or item_id == 20406    -- Twilight Cultist set
        or item_id == 11288 or item_id == 11290                    -- Enchanting-created wands
        or item_id == 11287 or item_id == 11289 then
        return {}
    end

    local id = de_id(quality, weapon, level)
    local loot = id and DE_LOOT[id]
    if not loot then
        return {}
    end

    local events = A()
    for _, e in ipairs(loot) do
        tinsert(events, O('item_id', e[1], 'min_quantity', e[2], 'max_quantity', e[3], 'probability', e[4]))
    end
    return events
end
