local f = io.open("items.txt", "rb");

local itemType, code, name, add, grp, text;

local output = {};
local class = 0;

local matches = {"Emblem .+", ".+ Trophy$", "Cycle", "Enchanting Crystal", "Wings of the Departed", ".+ Essence$", "Runestone", "^Great Rune|(.+)", "^Mystic Orb|(.+)"};

for line in f:lines() do
	code, name = line:match"%[.?(....)%] <(.*)>";
	if (code and name) then
		add = false;
		grp = "";
		text = "";

		if (itemType ~= "misc") then -- Weapons and armour
			add = true;
			grp = name:match"%(Sacred%)$" and "sacred" or "tiered";
			text = name;
		elseif (name=="Ring" or name=="Amulet" or name=="Jewel" or name:match"Quiver") then
			add = true;
			grp = "sacred";
			text = name;
		elseif (name:match"Shrine %(10%)") then
			add = true;
			grp = "shrine";
			text = name:gsub(" %(10%)$", "");
		elseif (name:match"Belladonna") then
			add = true;
			grp = "respec";
			text = name;
		elseif (name:match"Welcome") then
			add = true;
			text = "Hello!";
		else
			for _, match in ipairs (matches) do
				text = name:match(match) or "";
				if (text ~= "") then
					add = true;
					break;
				end
			end
		end

		table.insert(output, string.format('[%s,"%s","%s"], _ ; %s', add and "1" or "0", grp, text, line));
		class = class + 1;
	else
		code = line:match"{(%w+)}";
		itemType = code or itemType;
	end
end
f:close();

f = io.open("notify_list.au3", "w+b");
f:setvbuf"no";
f:write("global $notify_list[][3] = [ _\r\n", table.concat(output), "\r\n[] ]");
f:flush();
f:close();
