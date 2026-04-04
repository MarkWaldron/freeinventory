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

    local cross_bag = T{};
    local partial_stacks = T{};
    local slots_freeable = 0;

    for item_id, entries in pairs(grouped) do
        if (#entries < 2) then
            goto next_item;
        end

        local name = entries[1].name;
        local stack_size = entries[1].stack_size;

        -- Cross-bag duplicates: same item in different bags
        local bags_seen = T{};
        for _, e in ipairs(entries) do
            if (bags_seen[e.bag_id] == nil) then
                bags_seen[e.bag_id] = T{};
            end
            table.insert(bags_seen[e.bag_id], e);
        end

        local unique_bags = T{};
        for bag_id, _ in pairs(bags_seen) do
            table.insert(unique_bags, bag_id);
        end

        if (#unique_bags > 1) then
            local locations = T{};
            for _, e in ipairs(entries) do
                table.insert(locations, string.format('%s x%d', e.bag_name, e.count));
            end
            table.insert(cross_bag, {
                name      = name,
                locations = locations,
            });
        end

        -- Partial stacks in the same bag
        for bag_id, bag_entries in pairs(bags_seen) do
            if (#bag_entries > 1 and stack_size > 1) then
                local total = 0;
                for _, e in ipairs(bag_entries) do
                    total = total + e.count;
                end
                local stacks_needed = math.ceil(total / stack_size);
                local freed = #bag_entries - stacks_needed;
                if (freed > 0) then
                    slots_freeable = slots_freeable + freed;
                    table.insert(partial_stacks, {
                        name      = name,
                        bag_name  = get_container_name(bag_id),
                        stacks    = #bag_entries,
                        total     = total,
                        stack_size = stack_size,
                        freed     = freed,
                    });
                end
            end
        end

        ::next_item::
    end

    return cross_bag, partial_stacks, slots_freeable;
end

------------------------------------------------------------
-- Output
------------------------------------------------------------

local function report_dupes()
    local items = scan_inventory();
    local cross_bag, partial_stacks, slots_freeable = find_dupes(items);

    print(chat.header(addon.name):append(chat.message('Scanning ' .. #items .. ' items across all bags...')));

    -- Cross-bag dupes
    if (#cross_bag > 0) then
        print(chat.header(addon.name):append(chat.success('Cross-bag duplicates:')));
        for _, dupe in ipairs(cross_bag) do
            print(chat.header(addon.name)
                :append(chat.message('  ' .. dupe.name .. ' -> ' .. table.concat(dupe.locations, ', '))));
        end
    else
        print(chat.header(addon.name):append(chat.message('No cross-bag duplicates found.')));
    end

    -- Partial stacks
    if (#partial_stacks > 0) then
        print(chat.header(addon.name):append(chat.success('Partial stacks that can merge:')));
        for _, ps in ipairs(partial_stacks) do
            print(chat.header(addon.name)
                :append(chat.message(string.format('  %s in %s: %d stacks, %d total (max %d) - free %d slot(s)',
                    ps.name, ps.bag_name, ps.stacks, ps.total, ps.stack_size, ps.freed))));
        end
    else
        print(chat.header(addon.name):append(chat.message('No mergeable partial stacks found.')));
    end

    -- Summary
    if (slots_freeable > 0) then
        print(chat.header(addon.name)
            :append(chat.success(string.format('You can free %d slot(s) by merging partial stacks!', slots_freeable))));
    end

    print(chat.header(addon.name)
        :append(chat.message(string.format('Found %d cross-bag dupe(s), %d mergeable stack(s).',
            #cross_bag, #partial_stacks))));
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
