module 'aux.core.beancounter'

include 'aux'

function M.available()
	return _G.BeanCounter and _G.BeanCounter.API and _G.BeanCounter.API.isLoaded
end

function M.sold_failed(link, days)
	if not available() or not link then return end
	local player = UnitName('player')
	local ok, fail, ok_stk, fail_stk = _G.BeanCounter.API.getAHSoldFailed(player, link, days)
	return ok or 0, fail or 0, ok_stk or 0, fail_stk or 0
end

function M.last_bid(link, quantity)
	if not available() or not link or not quantity then return end
	local _, t, price = _G.BeanCounter.API.getBidReason(link, quantity)
	return price, t
end
