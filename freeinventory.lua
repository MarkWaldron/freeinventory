addon.name      = 'freeinventory';
addon.author    = 'MarkWaldron';
addon.version   = '1.0';
addon.desc      = 'Finds duplicate and partial stack items across all bags to free up inventory slots.';
addon.commands  = {'/freeinv'};

require('common');
local chat = require('chat');

------------------------------------------------------------
-- Container definitions
------------------------------------------------------------

local Containers = T{
    { id = 0,  name = 'Inventory' },
    { id = 1,  name = 'Safe' },
    { id = 2,  name = 'Storage' },
    { id = 4,  name = 'Locker' },
    { id = 5,  name = 'Satchel' },
    { id = 6,  name = 'Sack' },
    { id = 7,  name = 'Case' },
    { id = 8,  name = 'Wardrobe' },
    { id = 9,  name = 'Safe 2' },
    { id = 10, name = 'Wardrobe 2' },
    { id = 11, name = 'Wardrobe 3' },
    { id = 12, name = 'Wardrobe 4' },
    { id = 13, name = 'Wardrobe 5' },
    { id = 14, name = 'Wardrobe 6' },
    { id = 15, name = 'Wardrobe 7' },
    { id = 16, name = 'Wardrobe 8' },
};

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function get_item_name(res)
    -- Try each language index to find a readable English name
    for _, idx in ipairs({0, 2, 1, 3}) do
        local name = res.Name[idx];
        if (name ~= nil and #name > 0) then
            -- Check if it looks like ASCII/English (first char is printable ASCII)
            local b = string.byte(name, 1);
            if (b >= 0x20 and b <= 0x7E) then
                return name;
            end
        end
    end
    return res.Name[0] or res.Name[2] or 'Unknown';
end

local function get_container_name(bag_id)
    for _, c in ipairs(Containers) do
        if (c.id == bag_id) then return c.name; end
    end
    return 'Unknown';
end

local function scan_inventory()
    local inv = AshitaCore:GetMemoryManager():GetInventory();
    local resources = AshitaCore:GetResourceManager();
    local items = T{};

    for _, container in ipairs(Containers) do
        local max_slots = inv:GetContainerCountMax(container.id);
        if (max_slots == nil or max_slots == 0) then
            goto next_container;
        end

        -- Skip slot 0 of Inventory (gil)
        local start_slot = 0;
        if (container.id == 0) then start_slot = 1; end

        for slot = start_slot, max_slots - 1 do
            local entry = inv:GetContainerItem(container.id, slot);
            if (entry ~= nil and entry.Id ~= 0 and entry.Id ~= 65535) then
                local res = resources:GetItemById(entry.Id);
                if (res ~= nil) then
                    table.insert(items, {
                        id         = entry.Id,
                        name       = get_item_name(res),
                        count      = entry.Count,
                        stack_size = res.StackSize,
                        bag_id     = container.id,
                        bag_name   = container.name,
                        slot       = slot,
                    });
                end
            end
        end

        ::next_container::
    end

    return items;
end

------------------------------------------------------------
-- Dupe / partial stack detection
------------------------------------------------------------

local function find_dupes(items)
    -- Group items by ID
    local grouped = T{};
    for _, item in ipairs(items) do
        if (grouped[item.id] == nil) then
            grouped[item.id] = T{};
        end
        table.insert(grouped[item.id], item);
    end

    local partial_stacks = T{};
    local cross_bag_stackable = T{};
    local cross_bag_gear = T{};

    for item_id, entries in pairs(grouped) do
        if (#entries < 2) then
            goto next_item;
        end

        local name = entries[1].name;
        local stack_size = entries[1].stack_size;

        -- Group entries by bag
        local bags_seen = T{};
        for _, e in ipairs(entries) do
            if (bags_seen[e.bag_id] == nil) then
                bags_seen[e.bag_id] = T{};
            end
            table.insert(bags_seen[e.bag_id], e);
        end

        -- Partial stacks in the same bag (stackable items only)
        if (stack_size > 1) then
            for bag_id, bag_entries in pairs(bags_seen) do
                if (#bag_entries > 1) then
                    local total = 0;
                    local counts = T{};
                    for _, e in ipairs(bag_entries) do
                        total = total + e.count;
                        table.insert(counts, tostring(e.count));
                    end
                    local stacks_needed = math.ceil(total / stack_size);
                    local freed = #bag_entries - stacks_needed;
                    if (freed > 0) then
                        table.insert(partial_stacks, {
                            name       = name,
                            bag_name   = get_container_name(bag_id),
                            counts     = counts,
                            total      = total,
                            stack_size = stack_size,
                            freed      = freed,
                        });
                    end
                end
            end
        end

        -- Cross-bag duplicates
        local unique_bags = T{};
        for bag_id, _ in pairs(bags_seen) do
            table.insert(unique_bags, bag_id);
        end

        if (#unique_bags > 1) then
            local locations = T{};
            local total = 0;
            local current_slots = 0;
            for _, e in ipairs(entries) do
                table.insert(locations, string.format('%s x%d', e.bag_name, e.count));
                total = total + e.count;
                current_slots = current_slots + 1;
            end

            if (stack_size > 1) then
                local stacks_needed = math.ceil(total / stack_size);
                local freed = current_slots - stacks_needed;
                table.insert(cross_bag_stackable, {
                    name       = name,
                    locations  = locations,
                    total      = total,
                    stack_size = stack_size,
                    stacks_needed = stacks_needed,
                    freed      = freed,
                });
            else
                table.insert(cross_bag_gear, {
                    name      = name,
                    locations = locations,
                });
            end
        end

        ::next_item::
    end

    -- Sort by slots freed descending
    table.sort(partial_stacks, function(a, b) return a.freed > b.freed; end);
    table.sort(cross_bag_stackable, function(a, b) return a.freed > b.freed; end);

    return partial_stacks, cross_bag_stackable, cross_bag_gear;
end

------------------------------------------------------------
-- Output
------------------------------------------------------------

local function report_dupes()
    local items = scan_inventory();
    local partial_stacks, cross_bag_stackable, cross_bag_gear = find_dupes(items);

    print(chat.header(addon.name):append(chat.message('Scanning ' .. #items .. ' items across all bags...')));

    -- Section 1: Partial stacks in same bag (quick wins)
    local partial_freed = 0;
    for _, ps in ipairs(partial_stacks) do
        partial_freed = partial_freed + ps.freed;
    end

    if (#partial_stacks > 0) then
        print(chat.header(addon.name):append(chat.success(
            string.format('=== Quick wins: merge partial stacks (free %d slots) ===', partial_freed))));
        for _, ps in ipairs(partial_stacks) do
            print(chat.header(addon.name):append(chat.message(
                string.format('  %s in %s: %s = %d (max %d) -> free %d slot(s)',
                    ps.name, ps.bag_name, table.concat(ps.counts, '+'),
                    ps.total, ps.stack_size, ps.freed))));
        end
    else
        print(chat.header(addon.name):append(chat.message('No partial stacks to merge.')));
    end

    -- Section 2: Stackable cross-bag consolidation
    local cross_freed = 0;
    for _, cb in ipairs(cross_bag_stackable) do
        cross_freed = cross_freed + cb.freed;
    end

    if (#cross_bag_stackable > 0) then
        print(chat.header(addon.name):append(chat.success(
            string.format('=== Consolidate stackables across bags (free %d slots) ===', cross_freed))));
        for _, cb in ipairs(cross_bag_stackable) do
            print(chat.header(addon.name):append(chat.message(
                string.format('  %s: %s = %d/%d -> %d stack(s) (free %d)',
                    cb.name, table.concat(cb.locations, ' + '),
                    cb.total, cb.stack_size, cb.stacks_needed, cb.freed))));
        end
    else
        print(chat.header(addon.name):append(chat.message('No stackable cross-bag dupes found.')));
    end

    -- Section 3: Unstackable gear dupes (FYI)
    if (#cross_bag_gear > 0) then
        print(chat.header(addon.name):append(chat.message('=== FYI: unstackable dupes across bags ===')));
        for _, g in ipairs(cross_bag_gear) do
            print(chat.header(addon.name):append(chat.message(
                '  ' .. g.name .. ' -> ' .. table.concat(g.locations, ', '))));
        end
    end

    -- Summary
    local total_freed = partial_freed + cross_freed;
    if (total_freed > 0) then
        print(chat.header(addon.name):append(chat.success(
            string.format('Total: %d slot(s) freeable (%d from merging, %d from consolidating)',
                total_freed, partial_freed, cross_freed))));
    else
        print(chat.header(addon.name):append(chat.message('No slots to free right now.')));
    end
end

local function export_inventory()
    local items = scan_inventory();
    local path = string.format('%s/inventory.csv', addon.path);
    local f = io.open(path, 'w');
    if (f == nil) then
        print(chat.header(addon.name):append(chat.error('Failed to open file: ' .. path)));
        return;
    end

    f:write('Bag,Slot,Item ID,Item Name,Count,Stack Size\n');
    for _, item in ipairs(items) do
        f:write(string.format('%s,%d,%d,"%s",%d,%d\n',
            item.bag_name, item.slot, item.id, item.name:gsub('"', '""'), item.count, item.stack_size));
    end

    f:close();
    print(chat.header(addon.name):append(chat.success('Exported ' .. #items .. ' items to: ' .. path)));
end

------------------------------------------------------------
-- Events
------------------------------------------------------------

ashita.events.register('command', 'freeinv_command_cb', function (e)
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/freeinv')) then
        return;
    end
    e.blocked = true;

    if (#args >= 2 and args[2]:any('export')) then
        export_inventory();
        return;
    end

    if (#args >= 2 and args[2]:any('help')) then
        print(chat.header(addon.name):append(chat.message('Commands:')));
        print(chat.header(addon.name):append(chat.message('  /freeinv        - Scan for dupes and partial stacks')));
        print(chat.header(addon.name):append(chat.message('  /freeinv export - Export all inventory to CSV')));
        print(chat.header(addon.name):append(chat.message('  /freeinv help   - Show this help')));
        return;
    end

    -- Default: scan for dupes
    report_dupes();
end);

ashita.events.register('load', 'freeinv_load_cb', function ()
    print(chat.header(addon.name):append(chat.message('Loaded. Use /freeinv to scan, /freeinv export to save CSV.')));
end);

ashita.events.register('unload', 'freeinv_unload_cb', function ()
    print(chat.header(addon.name):append(chat.message('Unloaded.')));
end);
