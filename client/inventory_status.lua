-- DelPerroSands 2026-11-12: shows what the player knows about their own illness on the inventory
-- screen's status panel (DPS Inventory). Injuries and bleeding are read by the inventory itself;
-- this adds symptoms and anything a medic has diagnosed. It tells the player nothing they could
-- not already learn from /mystate: no hidden or incubating illness is sent.

local function send()
    if GetResourceState('ox_inventory') ~= 'started' then return end

    local state = lib.callback.await('dps-medical:getMyState', false) or {}
    local lines, seen = {}, {}

    for _, row in ipairs(state.diagnosed or {}) do
        if row.label and not seen[row.label] then
            seen[row.label] = true
            lines[#lines + 1] = { label = ('Diagnosed: %s'):format(row.label), severity = math.max(2, tonumber(row.severity) or 2) }
        end
    end

    for _, row in ipairs(state.symptoms or {}) do
        if row.label and not seen[row.label] then
            seen[row.label] = true
            lines[#lines + 1] = { label = row.label, severity = tonumber(row.severity) or 1 }
        end
    end

    pcall(function() exports.ox_inventory:setStatusLines(lines) end)
end

AddEventHandler('ox_inventory:statusOpened', function()
    CreateThread(send)
end)
