module 'aux.tabs.beancounter'

local gui = require 'aux.gui'
local listing_lib = require 'aux.gui.listing'

frame = CreateFrame('Frame', nil, AuxFrame)
frame:SetAllPoints()
frame:Hide()

frame.search_box = gui.editbox(frame)
frame.search_box:SetPoint('TOPLEFT', AuxFrame.content, 'TOPLEFT', 8, -8)
frame.search_box:SetPoint('TOPRIGHT', AuxFrame.content, 'TOPRIGHT', -8, -8)
frame.search_box:SetHeight(20)
frame.search_box:SetScript('OnTextChanged', function() set_filter(this:GetText()) end)

frame.panel = gui.panel(frame)
frame.panel:SetPoint('TOPLEFT', frame.search_box, 'BOTTOMLEFT', 0, -6)
frame.panel:SetPoint('TOPRIGHT', frame.search_box, 'BOTTOMRIGHT', 0, -6)
frame.panel:SetPoint('BOTTOMLEFT', AuxFrame.content, 'BOTTOMLEFT', 8, 8)
frame.panel:SetPoint('BOTTOMRIGHT', AuxFrame.content, 'BOTTOMRIGHT', -8, 8)

listing = listing_lib.new(frame.panel)
if listing.numRows == 0 then listing.numRows = 16 end
listing:SetColInfo{
	{name='Date',   width=.13, align='LEFT'},
	{name='Type',   width=.10, align='LEFT'},
	{name='Item',   width=.36, align='LEFT'},
	{name='Stack',  width=.07, align='RIGHT'},
	{name='Price',  width=.20, align='RIGHT'},
	{name='Party',  width=.14, align='LEFT'},
}
