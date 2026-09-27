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

addon.author   = 'MalRD, zombie343, sippius(v4), Haruuc, Hando';
addon.name     = 'Find';
addon.version  = '3.1.0h';

require('common');
local slips  = require('slips');
-- local struct = require('struct')
-- local bit    = require('bit')

local STORAGES = {
    [1] = { id=0, name='マイバッグ' },
    [2] = { id=1, name='モグ金庫' },
    [3] = { id=2, name='収納家具' },
    [4] = { id=3, name='テンポラリ' },
    [5] = { id=4, name='モグロッカー' },
    [6] = { id=5, name='モグサッチェル' },
    [7] = { id=6, name='モグサック' },
    [8] = { id=7, name='モグケース' },
    [9] = { id=8, name='モグワードローブ' },
    [10]= { id=9, name='モグ金庫2' },
    [11]= { id=10, name='モグワードローブ2' },
    [12]= { id=11, name='モグワードローブ3' },
    [13]= { id=12, name='モグワードローブ4' },
    [14]= { id=13, name='モグワードローブ5' },
    [15]= { id=14, name='モグワードローブ6' },
    [16]= { id=15, name='モグワードローブ7' },
    [17]= { id=16, name='モグワードローブ8' }
};

local VAULTSTORAGES = {};
for i = 0, 25 do
    local letter = string.char(string.byte('A') + i);
    VAULTSTORAGES[#VAULTSTORAGES + 1] = { id = 19 + i, name = 'ヴォルト預かり箱' .. letter };
    VAULTSTORAGES[#VAULTSTORAGES + 1] = { id = 45 + i, name = 'ヴォルトワードローブ' .. letter };
end
table.sort(VAULTSTORAGES, function(a, b)
    return a.id < b.id;
end);

local vault = {}

local default_config =
{
    language    =   1
};
local config = default_config;
local inventory = AshitaCore:GetMemoryManager():GetInventory();
local resources = AshitaCore:GetResourceManager();
-- Each container is Items[81] (indexes 0..80). CountMax can be 0, and then
-- a 0..max loop only reports the first slot.
local SLOT_LAST = 80;
local MINSLIP = 1;
local MAXSLIP = #slips.ids;

-- Resource strings are CP932. Chat input may already be UTF-8.
local ffi_ok, ffi = pcall(require, 'ffi');
if ffi_ok then
    pcall(ffi.cdef, [[
        int MultiByteToWideChar(uint32_t CodePage, uint32_t dwFlags, char* lpMultiByteStr, int cbMultiByte, wchar_t* lpMultiByteStr, int32_t cchWideChar);
        int WideCharToMultiByte(uint32_t CodePage, uint32_t dwFlags, wchar_t* lpWideCharStr, int32_t cchWideChar, char* lpMultiByteStr, int32_t cbMultiByte, const char* lpDefaultChar, bool* lpUsedDefaultChar);
    ]]);
end

local CP_UTF8 = 65001;
local CP_SJIS = 932;
local function has_high_byte(s)
    return type(s) == 'string' and s:find('[\128-\255]') ~= nil;
end

local function is_utf8(s)
    local i, n = 1, #s;
    while i <= n do
        local c = s:byte(i);
        if c < 0x80 then
            i = i + 1;
        elseif c >= 0xC2 and c <= 0xDF then
            local n1 = s:byte(i + 1);
            if not n1 or n1 < 0x80 or n1 > 0xBF then return false; end
            i = i + 2;
        elseif c >= 0xE0 and c <= 0xEF then
            local n1, n2 = s:byte(i + 1), s:byte(i + 2);
            if not n1 or not n2 or n1 < 0x80 or n1 > 0xBF or n2 < 0x80 or n2 > 0xBF then
                return false;
            end
            if c == 0xE0 and n1 < 0xA0 then return false; end
            i = i + 3;
        elseif c >= 0xF0 and c <= 0xF4 then
            local n1, n2, n3 = s:byte(i + 1), s:byte(i + 2), s:byte(i + 3);
            if not n1 or not n2 or not n3 then return false; end
            if n1 < 0x80 or n1 > 0xBF or n2 < 0x80 or n2 > 0xBF or n3 < 0x80 or n3 > 0xBF then
                return false;
            end
            i = i + 4;
        else
            return false;
        end
    end
    return true;
end

local function convert_codepage(input, from_cp, to_cp)
    if not ffi_ok or type(input) ~= 'string' or input == '' then
        return nil;
    end
    local source_length = #input;
    local cbuffer = ffi.new('char[?]', source_length + 1);
    ffi.copy(cbuffer, input);

    local wchar_length = ffi.C.MultiByteToWideChar(from_cp, 0, cbuffer, -1, nil, 0);
    if wchar_length <= 0 then
        return nil;
    end
    local wbuffer = ffi.new('wchar_t[?]', wchar_length);
    if ffi.C.MultiByteToWideChar(from_cp, 0, cbuffer, -1, wbuffer, wchar_length) <= 0 then
        return nil;
    end

    local char_length = ffi.C.WideCharToMultiByte(to_cp, 0, wbuffer, -1, nil, 0, nil, nil);
    if char_length <= 0 then
        return nil;
    end
    cbuffer = ffi.new('char[?]', char_length);
    if ffi.C.WideCharToMultiByte(to_cp, 0, wbuffer, -1, cbuffer, char_length, nil, nil) <= 0 then
        return nil;
    end
    return ffi.string(cbuffer);
end

-- Item names from the resource manager are Shift-JIS when they contain high bytes.
local function resource_to_utf8(s)
    if type(s) ~= 'string' or s == '' or not has_high_byte(s) then
        return s or '';
    end
    local converted = convert_codepage(s, CP_SJIS, CP_UTF8);
    if type(converted) == 'string' and converted ~= '' then
        return converted;
    end
    return s;
end

-- Chat text is UTF-8 when the bytes form valid UTF-8, otherwise CP932.
local function query_to_utf8(s)
    if type(s) ~= 'string' or s == '' or not has_high_byte(s) then
        return s or '';
    end
    if is_utf8(s) then
        return s;
    end
    local converted = convert_codepage(s, CP_SJIS, CP_UTF8);
    if type(converted) == 'string' and converted ~= '' then
        return converted;
    end
    return s;
end

-- Source text is UTF-8. The in-game log expects CP932. Resource strings are already CP932.
local function for_chat(s)
    if type(s) ~= 'string' or s == '' or not has_high_byte(s) then
        return s or '';
    end
    if is_utf8(s) then
        local converted = convert_codepage(s, CP_UTF8, CP_SJIS);
        if type(converted) == 'string' and converted ~= '' then
            return converted;
        end
    end
    return s;
end

for _, entry in ipairs(STORAGES) do
    entry.name = for_chat(entry.name);
end
for _, entry in ipairs(VAULTSTORAGES) do
    entry.name = for_chat(entry.name);
end

-- Map hiragana (U+3041..U+3096) onto katakana. Item names are katakana.
local function fold_kana(s)
    local out, i, n = {}, 1, #s;
    while i <= n do
        local b = s:byte(i);
        if b < 0x80 then
            out[#out + 1] = string.char(b);
            i = i + 1;
        elseif b >= 0xC2 and b <= 0xDF and i + 1 <= n then
            out[#out + 1] = s:sub(i, i + 1);
            i = i + 2;
        elseif b >= 0xE0 and b <= 0xEF and i + 2 <= n then
            local b2, b3 = s:byte(i + 1), s:byte(i + 2);
            local cp = ((b % 16) * 4096) + ((b2 % 64) * 64) + (b3 % 64);
            if cp >= 0x3041 and cp <= 0x3096 then
                cp = cp + 0x60;
                local e1 = 0xE0 + math.floor(cp / 4096);
                local e2 = 0x80 + (math.floor(cp / 64) % 64);
                local e3 = 0x80 + (cp % 64);
                out[#out + 1] = string.char(e1, e2, e3);
            else
                out[#out + 1] = s:sub(i, i + 2);
            end
            i = i + 3;
        elseif b >= 0xF0 and b <= 0xF4 and i + 3 <= n then
            out[#out + 1] = s:sub(i, i + 3);
            i = i + 4;
        else
            out[#out + 1] = string.char(b);
            i = i + 1;
        end
    end
    return table.concat(out);
end

-- Lowercase only after the string is UTF-8. string.lower corrupts raw Shift-JIS.
local function normalize_text(s, from_resource)
    local utf8 = from_resource and resource_to_utf8(s) or query_to_utf8(s);
    return fold_kana(utf8):lower();
end

local function field_at(arr, index)
    if arr == nil then return nil; end
    local ok, value = pcall(function()
        return arr[index];
    end);
    if ok and type(value) == 'string' and value ~= '' then
        return value;
    end
    return nil;
end

-- Raw resource string for the in-game log (CP932). Japanese query prefers a
-- non-ASCII name; an ASCII query prefers the English name.
local function display_name(item, prefer_japanese)
    if item == nil or item.Name == nil then return ''; end
    local ascii_name, jp_name;
    for i = 0, 3 do
        local name = field_at(item.Name, i);
        if name then
            if has_high_byte(name) then
                if jp_name == nil then jp_name = name; end
            elseif ascii_name == nil then
                ascii_name = name;
            end
        end
    end
    if prefer_japanese and jp_name then return jp_name; end
    if ascii_name then return ascii_name; end
    if jp_name then return jp_name; end
    return field_at(item.Name, config.language) or '';
end

-------------------------------------------------------------------------------
--Returns the real ID and name for the given inventory storage index.        --
-------------------------------------------------------------------------------
local function getStorage(storageIndex)
    return STORAGES[storageIndex].id, STORAGES[storageIndex].name;
end

-------------------------------------------------------------------------------
ashita.events.register('load', 'load_cb', function()
    -- print() during load is easy to miss; show the line on the next frame.
    ashita.tasks.once(0, function()
        printf('\30\08find を読み込みました。 (%s)', addon.version);
    end);
end );

-------------------------------------------------------------------------------
ashita.events.register('unload', 'unload_cb', function()
end );

-------------------------------------------------------------------------------
-- func : printf
-- desc : Because printing without formatting is for the birds.
-------------------------------------------------------------------------------
function printf(s,...)
    print(for_chat(s):format(...));
end;

-------------------------------------------------------------------------------
-- func: find
-- desc: Attempts to match the supplied cleanString to the supplied item.
-- args: item               -> the item being matched against.
--       cleanString        -> the cleaned string being searched for.
--       useDescription     -> true if the item description should be searched.
-- returns: true if a match is found, otherwise false.
-------------------------------------------------------------------------------
-- Resource strings are C buffers. Keep a short copy that stops at NUL so a
-- long log/description buffer cannot be used as a table key or chat line.
local MAX_LABEL = 96;

local function clean_label(raw)
    if type(raw) ~= 'string' or raw == '' then return nil; end
    local n = math.min(#raw, MAX_LABEL);
    local out = {};
    for i = 1, n do
        local b = raw:byte(i);
        if b == 0 then break; end
        if b < 0x20 then return nil; end
        out[#out + 1] = string.char(b);
    end
    if #out == 0 then return nil; end
    return table.concat(out);
end

local function label_matches(raw, needle)
    local label = clean_label(raw);
    if label == nil or needle == nil or needle == '' then return nil; end
    if normalize_text(label, true):find(needle, 1, true) == nil then return nil; end
    return label;
end

local function find(item, cleanString, useDescription)
    if (item == nil) then return false; end
    if (cleanString == nil or cleanString == '') then return false; end

    local matched = false;
    local function hits(raw)
        if label_matches(raw, cleanString) ~= nil then
            matched = true;
        end
    end

    for i = 0, 3 do
        hits(field_at(item.Name, i));
        hits(field_at(item.LogNameSingular, i));
        hits(field_at(item.LogNamePlural, i));
        if useDescription then
            hits(field_at(item.Description, i));
        end
    end

    if not matched then
        return false;
    end

    -- LogNamePlural is longer ("robes") and still contains the query ("robe").
    -- Show the item name, not that log line.
    local preferJapanese = has_high_byte(cleanString);
    return true, clean_label(display_name(item, preferJapanese)) or '';
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
    local cleanString = AshitaCore:GetChatManager():ParseAutoTranslate(searchString, false);

    if (cleanString == nil) then return; end
    local folded = normalize_text(cleanString, false);
    local preferJapanese = has_high_byte(cleanString);

    printf('\30\08"%s"を探しています...', for_chat(cleanString));
    local inventory = AshitaCore:GetMemoryManager():GetInventory();
    local resources = AshitaCore:GetResourceManager();

    local found = { };
    local result = { };
    local storageSlips = { };

    local slipNeedle = normalize_text('storage slip ', false);

    for k,v in ipairs(STORAGES) do
        for j = 0, SLOT_LAST do
            local okEntry, itemEntry = pcall(function()
                return inventory:GetContainerItem(v.id, j);
            end);
            if okEntry and itemEntry ~= nil then
                local itemId = tonumber(itemEntry.Id) or 0;
                if (itemId ~= 0 and itemId ~= 65535) then
                    local item = resources:GetItemById(itemId);

                    if (item ~= nil) then
                        local matched, matchedName = find(item, folded, useDescription);
                        if (matched) then
                            local quantity = 1;
                            local stack = tonumber(item.StackSize) or 1;
                            local count = tonumber(itemEntry.Count);
                            if (count ~= nil and stack > 1) then
                                quantity = count;
                            end

                            if result[k] == nil then
                                result[k] = { };
                                found[k] = { };
                            end

                            -- Same item id stacks onto one line. Different ids stay separate
                            -- even when the Japanese labels would not make unique table keys.
                            local name = matchedName;
                            if name == nil or name == '' then
                                name = clean_label(display_name(item, preferJapanese)) or '';
                            end
                            local row = found[k][itemId];
                            if row == nil then
                                row = { name = name, count = 0 };
                                found[k][itemId] = row;
                                result[k][#result[k] + 1] = row;
                            end

                            row.count = row.count + quantity;
                        end

                        if find(item, slipNeedle, false) then
                            local extra = itemEntry.Extra;
                            if type(extra) == 'string' then
                                extra = extra:sub(1);
                            end
                            storageSlips[#storageSlips + 1] = { id = itemId, extra = extra };
                        end
                    end
                end
            end
        end
    end

    local total = 0;
    for k,v in ipairs(STORAGES) do
        if result[k] ~= nil then
            storageID, storageName = getStorage(k);
            for i = 1, #result[k] do
                local item = result[k][i];
                local line = storageName .. ': ' .. item.name;
                if item.count > 1 then
                    line = line .. string.format(' [%d]', item.count);
                end
                print(line);
                total = total + item.count;
            end
        end
    end

    for k,v in ipairs(storageSlips) do
        local slip = resources:GetItemById(v.id);
        local slipItems = slips.items[v.id];
        local extra = v.extra;

        for i,slipItemID in ipairs(slipItems) do
            local slipItem = resources:GetItemById(slipItemID);
            local matched, matchedName = find(slipItem, folded, useDescription);
            if (matched) then
                local byte = struct.unpack('B',extra,math.floor((i - 1) / 8)+1);
                if byte < 0 then
                    byte = byte + 256;
                end

                if (hasBit(byte, bit((i - 1) % 8 + 1))) then
                    printf('%s: %s', display_name(slip, preferJapanese), matchedName or display_name(slipItem, preferJapanese));
                    total = total + 1;
                end
            end
        end
    end

    for _,v in ipairs(VAULTSTORAGES) do
        if vault[v.id] ~= nil then
            for itemID, qty in pairs(vault[v.id]) do
                local vaultItem = resources:GetItemById(itemID)
                local matched, matchedName = find(vaultItem, folded, useDescription);
                if (matched) then
                    quantity = '';
                    if qty > 1 then
                        quantity = string.format('[%d]', qty)
                    end
                    printf('%s: %s %s', v.name, matchedName or display_name(vaultItem, preferJapanese), quantity);
                    total = total + qty;
                end
            end
        end
    end

    printf('\30\08%d個見つかりました。', total);
end

-------------------------------------------------------------------------------
function bit(p)
    return 2 ^ (p - 1);
 end

-------------------------------------------------------------------------------
function hasBit(x, p)
    return x % (p + p) >= p;
end

local function findinslip(searchslip, item)
    if (item == nil) then
        return nil,nil
    end;

    if searchslip == 0 then
        for k,v in pairs(slips.items) do
            local slip = resources:GetItemById(k);
            for x = 1, #v do
                if item.Id == v[x] then
                    local slipItem = resources:GetItemById(item.Id);
                    --printf('%s: %s', slip.Name[config.language], slipItem.Name[config.language]);
                    return display_name(slip, false), display_name(slipItem, false);
                end
            end
        end
    elseif searchslip >= MINSLIP and searchslip <= MAXSLIP then
        local slip = resources:GetItemById(slips.ids[searchslip]);
        for x = 1, #slips.items[slips.ids[searchslip]] do
            if item.Id == slips.items[slips.ids[searchslip]][x] then
                local slipItem = resources:GetItemById(item.Id);
                --printf('%s: %s', slip.Name[config.language], slipItem.Name[config.language]);
                return display_name(slip, false), display_name(slipItem, false);
            end
        end
    else
        printf('\30\08収納スリップは%iから%iの間で指定してください。', MINSLIP, MAXSLIP);
    end
    return nil,nil;
end


-------------------------------------------------------------------------------
local function getFindArgs(cmd)
    if (not cmd:find('/find', 1, true)) then return nil; end

    local indexOf = cmd:find(' ', 1, true);
    if (cmd:find('/findslips', 1, true) or cmd:find('/finddupes', 1, true)) and indexOf == nil then
        cmdTable =     {
            [1] = cmd
        };
        return cmdTable;
    end

    --Specific /findxyz command inputs that require second argument but don't have one specified
    if indexOf == nil then
        return nil;
    end

    --All other inputs that have /find and a space " ", return both words:
    cmdTable =     {
        [1] = cmd:sub(1,indexOf-1),
        [2] = cmd:sub(indexOf+1),
    };

    return cmdTable;
end

-------------------------------------------------------------------------------
-- func: printslips
-- desc: Searches the player's inventory for any items that can be stored in
--       storage slips.
--
-- args: searchslip     -> Indicates search all slips (0) OR specifies slip to
--                         search for (1-27 index into slip_data:slip.items[])
-------------------------------------------------------------------------------
local function printslips(searchslip)

    local found = { };
    local foundSlip, foundItem;
    local result = { };
    local keyset = {};

    if searchslip == 0 then
        printf('\30\08収納スリップにしまえるアイテムを探しています...');
    elseif searchslip >= MINSLIP and searchslip <= MAXSLIP then
        printf('\30\08収納スリップ#%iにしまえるアイテムを探しています...', searchslip);
    else
        printf('\30\08収納スリップは%iから%iの間で指定してください。', MINSLIP, MAXSLIP);
        return;
    end

    for k,v in ipairs(STORAGES) do
        for j = 0, SLOT_LAST do
            local okEntry, itemEntry = pcall(function()
                return inventory:GetContainerItem(v.id, j);
            end);
            local itemId = okEntry and itemEntry ~= nil and tonumber(itemEntry.Id) or 0;
            if (itemId ~= 0 and itemId ~= 65535) then
                local item = resources:GetItemById(itemId);
                if (item ~= nil) then
                    --printf('%s: %s', item.Name[config.language], itemEntry.Id)
                    foundSlip,foundItem = findinslip(searchslip, itemEntry)
                    if (foundSlip ~= nil) then
                        --keyset[#keyset+1] = foundSlip
                        --printf('%s: %s', foundSlip, foundItem)
                        --result[foundSlip] = foundItem;
                        --table.insert(found, foundItem)
                        if result[foundSlip] == nil then
                            result[foundSlip] = {}
                            table.insert(result[foundSlip], foundItem);
                            keyset[#keyset+1] = foundSlip
                            --result[foundSlip][itemEntry] = {};
                        else
                            table.insert(result[foundSlip], foundItem);
                            --result[foundSlip].itemEntry = item.Name
                        end
                    end
                end
            end
        end
    end

    --table.sort()
    local keysize = #keyset;
    local resultsize = 0;
    if keysize > 0 then
        table.sort(keyset)
        for slipIndex=1, keysize, 1 do
            for _,item in pairs(result[keyset[slipIndex]]) do
                printf('%s: %s', keyset[slipIndex],item);
                resultsize = resultsize + 1;
            end
        end
        if searchslip == 0 then
            printf('\30\08しまえるアイテムが%i個、%i種類のスリップに見つかりました。', resultsize, keysize);
        else
            printf('\30\08収納スリップ#%iにしまえるアイテムが%i個見つかりました。', searchslip, resultsize);
        end
    else
        printf('\30\08収納スリップにしまえるアイテムは見つかりませんでした。');
    end
end

-------------------------------------------------------------------------------
-- func: printdupes
-- desc: Searches the player's inventory for items that occupy more than one
--       inventory slot. (Note, stacks or single items will both count as 1.
--       Therefore, 2 stacks of 99 HP-Bayld will have a count of 2.)
--
-- args: none
--
-------------------------------------------------------------------------------
local function printdupes()

    local result = { };
    local dupes = {};
    local resultsize = 0;
    local dupesize = 0;

    printf('\30\08重複しているアイテムを探しています...');
    for k,v in ipairs(STORAGES) do
        for j = 0, SLOT_LAST do
            local okEntry, itemEntry = pcall(function()
                return inventory:GetContainerItem(v.id, j);
            end);
            local itemId = okEntry and itemEntry ~= nil and tonumber(itemEntry.Id) or 0;
            if (itemId ~= 0 and itemId ~= 65535) then
                local item = resources:GetItemById(itemId);
                if (item ~= nil) then
                    if result[itemId] == nil then
                        result[itemId] = 1;
                    else
                        cnt = result[itemId] + 1
                        result[itemId] = cnt;
                        if cnt == 2 then
                            resultsize = resultsize + 1;
                        end
                    end
                    --printf('(itemName)=%s: (itemID):%s, (result[itemID]):%s', item.Name[config.language], item.ItemId, result[item.ItemId]);
                end
            end
        end
    end

    for _,v in ipairs(VAULTSTORAGES) do
        if vault[v.id] ~= nil then
            for itemID, _ in pairs(vault[v.id]) do
                local vaultItem = resources:GetItemById(itemID)
                if (vaultItem ~= nil) then
                    if result[vaultItem.Id] == nil then
                        result[vaultItem.Id] = 1;
                    else
                        cnt = result[vaultItem.Id] + 1
                        result[vaultItem.Id] = cnt;
                        if cnt == 2 then
                            resultsize = resultsize + 1;
                        end
                    end
                end
            end
        end
    end

    dupesize = 0;
        if (resultsize > 0) then
            for id,cnt in pairs(result) do
                if ( tonumber(cnt) > 1 ) then
                    --printf('I %s: %d', id, cnt);
                    local dupeitem = resources:GetItemById(id);
                    dupes[id] = { name = display_name(dupeitem, false), count=cnt };
                    dupesize = dupesize + 1;
                end
            end
        end

        if (dupesize > 0) then
            for k,v in pairs(dupes) do
                printf('%s: %d', v.name, v.count);
            end
            printf('\30\08重複しているアイテムが%i種類見つかりました。', dupesize);
        else
            printf('\30\08重複しているアイテムは見つかりませんでした。');
            return true;
        end

end

ashita.events.register('packet_in', 'find_pkt', function(e)
    if e.id == 0x1A1 then
        local itemID     = struct.unpack('H', e.data, 5)  -- uint16 @ 0x04
        local quantity   = struct.unpack('H', e.data, 7)  -- uint16 @ 0x06
        local locationID = struct.unpack('B', e.data, 9)  -- uint8  @ 0x08
        local update     = struct.unpack('B', e.data, 11) -- uint8  @ 0x0A

        -- printf('locationID: %d, itemID: %d, quantity: %d', locationID, itemID, quantity)
        -- If this packet signals a fresh update, reset vault
        if update == 1 then
            -- printf("Clearing vault cache, here's what was in it:")
            -- for locationID, v in pairs(vault) do
            --     printf('location %d:', locationID)
            --     for itemID, qty in pairs(v) do
            --         printf('  %d x%d', itemID, qty)
            --     end
            -- end
            vault = {}
        end

        vault[locationID] = vault[locationID] or {}
        vault[locationID][itemID] = quantity
    end
end)

-------------------------------------------------------------------------------
ashita.events.register('command', 'command_cb', function(e)
    local args = getFindArgs(e.command);
    if (args == nil) then return false; end

    if (args[1]:lower() == '/find' and #args <= 2) then
        search(args[2], false);
        return true;
    elseif (args[1]:lower() == '/findmore' and #args <= 2) then
        search(args[2], true);
        return true;
    elseif (args[1]:lower() == '/finddupes' and #args <= 1) then
        printdupes();
        return true;
    elseif (args[1]:lower() == '/findslips' and #args <= 2) then
        if #args >= 2 then
            searchslip = tonumber(args[2]:lower());
            if not searchslip then
                printf('\30\08収納スリップは%iから%iの間で指定してください。', MINSLIP, MAXSLIP);
                return false;
            else
                printslips(searchslip);
                return true;
            end
        else
            printslips(0);
        end
    end;
    return false;
end );
