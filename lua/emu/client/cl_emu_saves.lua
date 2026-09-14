-- Saves stay on the player's disk, outside CEF storage and Workshop archives.
if not CLIENT then return end
emu = emu or {}
local LIMIT = 8 * 1024 * 1024 + 4096

local function valid(data, system, rom)
    if not isstring(data) or #data > LIMIT then return false end
    local record = util.JSONToTable(data)
    if not istable(record) or record.system ~= system or record.rom ~= rom
        or not isstring(record.state) or #record.state == 0 or #record.state > LIMIT - 4096 then return false end
    return record.version == 2 and record.checksum == util.CRC(record.state), record
end

function emu.SaveDirectory(system, rom)
    return "emu/saves/" .. system .. "/" .. rom:gsub("[^%w_%-]", "_"):sub(1, 64) .. "_" .. util.CRC(rom)
end

function emu.WriteSaveSlot(dir, slot, data, system, rom)
    local good, record = valid(data, system, rom)
    if not good then return false, "Invalid save record" end
    file.CreateDir(dir)
    local path = dir .. "/" .. slot .. ".json"
    local backup, pending = path .. ".previous.json", path .. ".pending.json"
    local current = file.Read(path, "DATA")
    local currentGood, currentRecord = valid(current, system, rom)
    if currentGood and currentRecord.state == record.state and currentRecord.romIdentity == record.romIdentity
        and currentRecord.build == record.build then return true end
    file.Write(pending, data)
    if file.Read(pending, "DATA") ~= data then return false, "Unable to write save; check free disk space" end
    -- Rotate only a verified primary. A corrupt primary must not destroy the good backup.
    if currentGood then
        file.Write(backup .. ".pending.json", current)
        if file.Read(backup .. ".pending.json", "DATA") ~= current then file.Delete(pending) return false, "Unable to preserve previous save" end
        file.Delete(backup)
        file.Rename(backup .. ".pending.json", backup)
        if file.Read(backup, "DATA") ~= current then file.Delete(pending) return false, "Unable to preserve previous save" end
    end
    file.Delete(path) -- Source's Windows filesystem does not guarantee rename-overwrite.
    file.Rename(pending, path)
    if file.Read(path, "DATA") ~= data then
        -- A failed replacement must leave a usable primary or previous file.
        if currentGood then file.Write(path, current) end
        return false, "Unable to replace save file; previous save retained"
    end
    return true
end

function emu.BindSaveStorage(frame, html)
    local function reply(id, ok, data)
        if IsValid(html) then
            html:QueueJavascript("if(window.EmuSaveIO) EmuSaveIO.complete.apply(null," .. util.TableToJSON({id,ok,data or ""}) .. ");")
        end
    end
    local function pathFor(id, slot)
        if not IsValid(frame) or not IsValid(html) or (emu.ActiveWindow ~= frame and not frame.Closing) then return end
        if not isnumber(id) or id < 1 or id > 2147483647 or id % 1 ~= 0 then return end
        if slot ~= "1" and slot ~= "2" and slot ~= "3" and slot ~= "auto" then reply(id,false,"Invalid slot") return end
        return emu.SaveDirectory(frame.Profile.id, frame.RomName)
    end
    html:AddFunction("gmod", "readSaveSlot", function(id, slot)
        local dir=pathFor(id,slot)
        if not dir then return end
        local path=dir .. "/" .. slot .. ".json"
        local function read(path)
            if file.Size(path,"DATA") > LIMIT then return "invalid oversized save" end
            return file.Read(path,"DATA")
        end
        local attempts=0
        local function restore()
            if not IsValid(frame) or not IsValid(html) then return end
            for closing in pairs(emu.ClosingSaveFrames or {}) do
                if not IsValid(closing) then emu.ClosingSaveFrames[closing]=nil
                elseif closing ~= frame and closing.Profile.id == frame.Profile.id and closing.RomName == frame.RomName then
                    attempts=attempts+1
                    if attempts>=60 then reply(id,false,"Previous session is still saving; old files preserved") return end
                    timer.Simple(0.05,restore)
                    return
                end
            end
            reply(id,true,util.TableToJSON({current=read(path),previous=read(path .. ".previous.json") or read(path .. ".previous")}))
        end
        restore()
    end)
    html:AddFunction("gmod", "writeSaveSlot", function(id, slot, data)
        local dir=pathFor(id,slot)
        if not dir then return end
        local ok,err=emu.WriteSaveSlot(dir,slot,data,frame.Profile.id,frame.RomName)
        reply(id,ok,err)
    end)
end
