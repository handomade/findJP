--[[
 *  The MIT License (MIT)
 *
 *  Copyright (c) 2014 MalRD
 *  
 *  Permission is hereby granted, free of charge, to any person obtaining a copy
 *  of this software and associated documentation files (the "Software"), to 
 *  deal in the Software without restriction, including without limitation the 
 *  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or 
 *  sell copies of the Software, and to permit persons to whom the Software is 
 *  furnished to do so, subject to the following conditions:
 *  
 *  The above copyright notice and this permission notice shall be included in 
 *  all copies or substantial portions of the Software.
 *  
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING 
 *  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
 *  DEALINGS IN THE SOFTWARE.
]]--

_addon.author   = 'MalRD';
_addon.name     = 'Find';
_addon.version  = '3.0.0';

local slips = require('slips');

local STORAGES = {
    [1] = { id=0, name='Inventory' },
    [2] = { id=1, name='Safe' },
    [3] = { id=2, name='Storage' },
    [4] = { id=3, name='Temporary' },
    [5] = { id=4, name='Locker' },
    [6] = { id=5, name='Satchel' },
    [7] = { id=6, name='Sack' },
    [8] = { id=7, name='Case' },
    [9] = { id=8, name='Wardrobe' },
    [10]= { id=9, name='Safe 2' },
    [11]= { id=10, name='Wardrobe 2' },
    [12]= { id=11, name='Wardrobe 3' },
    [13]= { id=12, name='Wardrobe 4' }
};

local default_config = 
{
    language    =   0
};
local config = default_config;

-------------------------------------------------------------------------------
--Returns the real ID and name for the given inventory storage index.        --
-------------------------------------------------------------------------------
local function getStorage(storageIndex)
    return STORAGES[storageIndex].id, STORAGES[storageIndex].name;
end

-------------------------------------------------------------------------------
ashita.register_event('load', function()
end );

-------------------------------------------------------------------------------
ashita.register_event('unload', function()
end );

-------------------------------------------------------------------------------
-- func : printf
-- desc : Because printing without formatting is for the birds.
-------------------------------------------------------------------------------
function printf(s,...)
    print(s:format(...));
end;

-------------------------------------------------------------------------------
-- func: find
-- desc: Attempts to match the supplied cleanString to the supplied item.
-- args: item               -> the item being matched against.
--       cleanString        -> the cleaned string being searched for.
--       useDescription     -> true if the item description should be searched.
-- returns: true if a match is found, otherwise false.
-------------------------------------------------------------------------------
local function find(item, cleanString, useDescription)
    if (item == nil) then return false end;
    if (cleanString == nil) then return false end;

    if (string.lower(item.Name[config.language]):find(cleanString)) then
        return true;
    elseif (item.LogNameSingular[config.language] ~= nil and string.lower(item.LogNameSingular[config.language]):find(cleanString)) then
        return true;
    elseif (item.LogNamePlural[config.language] ~= nil and string.lower(item.LogNamePlural[config.language]):find(cleanString)) then
        return true;
    elseif (useDescription and item.Description ~= nil) then
        return (string.lower(item.Description[config.language]):find(cleanString));
    end
    
    return false;
end

-------------------------------------------------------------------------------
-- func: search
-- desc: Searches the player's inventory for an item that matches the supplied 
--       string.
-- args: searchString       -> the string that is being searched for.
--       useDescription     -> true if the item description should be searched.
-------------------------------------------------------------------------------
local function search(searchString, useDescription) 
    if (searchString == nil) then return; end
    local cleanString = ParseAutoTranslate(searchString, false);
    
    if (cleanString == nil) then return; end
    cleanString = string.lower(cleanString);
    
    printf("\30\08Finding \"%s\"...", cleanString);
    local inventory = AshitaCore:GetDataManager():GetInventory();
    local resources = AshitaCore:GetResourceManager();
    
    local found = { };
    local result = { };
    local storageSlips = { };
    
    for k,v in ipairs(STORAGES) do
        local foundCount = 1;
        for j = 0, inventory:GetContainerMax(v.id), 1 do
            local itemEntry = inventory:GetItem(v.id, j);
            if (itemEntry.Id ~= 0 and itemEntry.Id ~= 65535) then
                local item = resources:GetItemById(itemEntry.Id);
                
                if (item ~= nil) then
                    if (find(item, cleanString, useDescription)) then
                        quantity = 1;
                        if (itemEntry.Count ~= nil and item.StackSize > 1) then
                            quantity = itemEntry.Count;
                        end
                    
                        if result[k] == nil then 
                            result[k] = { }; 
                            found[k] = { };
                        end
                        
                        if found[k][itemEntry.Id] == nil then
                            found[k][itemEntry.Id] = foundCount;
                            result[k][foundCount] = { name = item.Name[config.language], count = 0 };
                            foundCount = foundCount + 1;
                        end
                                                                                                
                        result[k][found[k][itemEntry.Id]].count = result[k][found[k][itemEntry.Id]].count + quantity;
                    end
                    
                    if find(item, 'storage slip ', false) then
                        storageSlips[#storageSlips + 1] = {item, itemEntry};
                    end
                end
            end
        end
    end
    
    local total = 0;
    for k,v in ipairs(STORAGES) do
        if result[k] ~= nil then
            storageID, storageName = getStorage(k);
            for _,item in ipairs(result[k]) do
                quantity = '';
                if item.count > 1 then 
                    quantity = string.format('[%d]', item.count)
                end
                printf('%s: %s %s', storageName, item.name, quantity);
                total = total + item.count;
            end
        end
    end
    
    for k,v in ipairs(storageSlips) do
        local slip = resources:GetItemById(v[1].ItemID);
        local slipItems = slips.items[v[1].ItemID];
        local extra = v[2].Extra;
        
        for i,slipItemID in ipairs(slipItems) do
            local slipItem = resources:GetItemById(slipItemID);
            if (find(slipItem, cleanString, useDescription)) then
                local byte = extra[math.floor((i - 1) / 8)];
                if byte < 0 then
                    byte = byte + 256;
                end
                
                if (hasBit(byte, bit((i - 1) % 8 + 1))) then
                    printf('%s: %s', slip.Name[config.language], slipItem.Name[config.language]);
                    total = total + 1;
                end
            end
        end
    end
    
    printf('\30\08Found %d matching items.', total);
end

-------------------------------------------------------------------------------
function bit(p) 
    return 2 ^ (p - 1);
 end
 
-------------------------------------------------------------------------------
function hasBit(x, p) 
    return x % (p + p) >= p;
end

-------------------------------------------------------------------------------
local function getFindArgs(cmd)
    if (not cmd:find('/find', 1, true)) then return nil; end
    
    local indexOf = cmd:find(' ', 1, true);
    if (indexOf == nil) then return nil; end
    
    return
    { 
        [1] = cmd:sub(1,indexOf-1),  
        [2] = cmd:sub(indexOf+1)
    };
end

-------------------------------------------------------------------------------
ashita.register_event('command', function(cmd, nType)
    local args = getFindArgs(cmd);
    if (args == nil or #args < 2) then return false; end
    
    if (args[1]:lower() == '/find') then
        search(args[2]:lower(), false);
        return true;
    elseif (args[1]:lower() == '/findmore') then
        search(args[2]:lower(), true);
        return true;
    end;
    
    return false;
end );