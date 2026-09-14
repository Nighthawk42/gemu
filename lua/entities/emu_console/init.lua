-- SNES Console Entity Server
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:SpawnFunction(ply, tr, ClassName)
    if not tr.Hit or tr.HitNormal.z < 0.7 then
        ply:ChatPrint("GEMU: Aim at a reasonably level surface to spawn a console and TV.")
        return
    end
    local profile = emu.Systems[self.SystemID or "snes"]

    -- Console faces the player who spawned it
    local spawnAng = Angle(0, ply:EyeAngles().yaw, 0)
    local spawnPos = tr.HitPos + tr.HitNormal * 2

    local console = ents.Create(ClassName)
    if not IsValid(console) then return end
    console:SetPos(spawnPos)
    console:SetAngles(spawnAng)
    console:Spawn()
    console:Activate()

    -- Spawn CRT TV to the left of the console (player's left)
    local crtPos = console:LocalToWorld(profile.display.spawnOffset)
    local crtAng = console:LocalToWorldAngles(profile.display.spawnAngles)

    local crt = ents.Create("emu_crt")
    if not IsValid(crt) then console:Remove() return end
    crt:SetPos(crtPos)
    crt:SetAngles(crtAng)
    crt:Spawn()
    crt:Activate()

    -- Settle each prop onto its own surface, then reject obstructed placement.
    for _, ent in ipairs({console, crt}) do
        local ground = util.TraceLine({start = ent:GetPos() + Vector(0, 0, 32),
            endpos = ent:GetPos() - Vector(0, 0, 64), filter = {console, crt, ply}})
        if not ground.Hit or ground.HitNormal.z < 0.7 then
            ply:ChatPrint("GEMU: There is no level surface beneath the console and TV. Try a wider clear area.")
            console:Remove() crt:Remove() return
        end
        ent:SetPos(Vector(ent:GetPos().x, ent:GetPos().y, ground.HitPos.z - ent:OBBMins().z + 1))
        local mins, maxs = ent:WorldSpaceAABB()
        local clear = util.TraceHull({start = ent:GetPos(), endpos = ent:GetPos(),
            mins = mins - ent:GetPos(), maxs = maxs - ent:GetPos(), filter = {console, crt, ply}})
        if clear.Hit then
            ply:ChatPrint("GEMU: The console or TV would intersect another object. Try a clear area.")
            console:Remove() crt:Remove() return
        end
        ent:SetCreator(ply)
        ply:AddCleanup("emulators", ent)
    end

    console:SetLinkedDisplay(crt)
    crt:SetLinkedConsole(console)

    -- Spawn initial Super Mario World cartridge inserted (Skin 4)
    local cart = ents.Create(profile.cartridgeClass)
    if not IsValid(cart) then console:Remove() crt:Remove() return end
    cart:SetPos(spawnPos + Vector(0, 0, 10))
    cart:SetAngles(spawnAng)
    cart:Spawn()
    cart:Activate()
    cart:SetRomName(profile.defaultRom)
    cart:SetGameTitle(profile.defaultGame)
    cart:SetCartridgeSkin(profile.defaultSkin)
    cart:SetSkin(profile.defaultSkin)

    cart:SetCreator(ply)
    console:InsertCartridgeEntity(cart, ply)
    ply:AddCleanup("emulators", cart)

    -- Single Undo Group
    undo.Create(profile.name .. " + CRT")
    undo.AddEntity(console)
    undo.AddEntity(crt)
    undo.AddEntity(cart)
    undo.SetPlayer(ply)
    undo.Finish()

    return console
end

function ENT:Initialize()
    local profile = emu.Systems[self.SystemID or "snes"]
    self:SetModel(profile.consoleModel)
    self:SetUseType(SIMPLE_USE)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
    end

    self:SetSystemId(profile.id)
    self:SetPower(false)
    self:SetHasCartridge(false)
    self:SetCartridgeSkin(0)
    self:SetSkin(0)
    self:SetGameTitle("No Cartridge")
    self:SetRomName("")
    self:SetRomUrl("")

    -- Bodygroup 3: 0 = cartridge_snes; 1 = no_cartridge.
    -- Bodygroup 2's snes_cable.smd is an unattached second-controller cable.
    -- The visible controller in bodygroup 4 already includes its own cord.
    for index, value in pairs(profile.initialBodygroups or {}) do self:SetBodygroup(index,value) end
    if profile.cartridgeBodygroup then self:SetBodygroup(profile.cartridgeBodygroup,profile.cartridgeEmpty) end

    self.EjectCooldown = 0
end

function ENT:PreEntityCopy()
    if not duplicator or not duplicator.StoreEntityModifier then return end
    local links = {}
    local display, cart = self:GetLinkedDisplay(), self:GetInsertedCart()
    if IsValid(display) then links.display = display:EntIndex() end
    if IsValid(cart) then links.cart = cart:EntIndex() end
    duplicator.StoreEntityModifier(self, "EmuLinks", links)
end

function ENT:PostEntityPaste(_, ent, createdEntities)
    -- Sessions belong to live clients; a pasted copy starts unreserved.
    if self.SetControllingPlayer then self:SetControllingPlayer(NULL) end
    if self.SetPlayer2 then self:SetPlayer2(NULL) end
    if self.SetSessionPaused then self:SetSessionPaused(false) end
    local links = ent.EntityMods and ent.EntityMods.EmuLinks
    if not links then return end
    emu.RelinkConsole(self, emu.PastedEntity(createdEntities, links.display), emu.PastedEntity(createdEntities, links.cart))
end

function ENT:InsertCartridgeEntity(cart, ply)
    if not IsValid(cart) or not cart.IsEmuCartridge then return false end
    if not emu.CanInsertCartridge(ply, self, cart) then return false end
    if cart:GetSystemId() ~= self:GetSystemId() then return false end
    if self.EjectCooldown and CurTime() < self.EjectCooldown then return false end
    if self:GetHasCartridge() then return false end

    local current = cart:GetCurrentConsole()
    if IsValid(current) and current ~= self then return false end

    local skin = cart:GetCartridgeSkin()
    if self:GetSystemId() == "snes" and skin == 0 and not (cart.GetBlankCartridge and cart:GetBlankCartridge())
        and (cart:GetRomName() == "super_mario_world.smc" or cart:GetGameTitle() == "Super Mario World") then
        skin = 4
    end

    cart:SetMoveType(MOVETYPE_NONE)
    cart:SetSolid(SOLID_NONE)
    cart:SetParent(self)
    -- Align cartridge standing vertically upright in slot with label facing forward towards player
    local profile = emu.GetSystem(self)
    cart:SetLocalPos(profile.cartridgePosition)
    cart:SetLocalAngles(profile.cartridgeAngles)
    cart:SetIsInserted(true)
    cart:SetCurrentConsole(self)

    self:SetHasCartridge(true)
    self.EmuHandoffState = nil
    self:SetInsertedCart(cart)
    self:SetBlankCartridge(cart.GetBlankCartridge and cart:GetBlankCartridge() or false)
    self:SetGameTitle(cart:GetGameTitle())
    self:SetRomName(cart:GetRomName())
    self:SetRomUrl(cart:GetRomUrl())
    self:SetCartridgeSkin(skin)
    self:SetSkin(skin)
    if profile.cartridgeBodygroup then self:SetBodygroup(profile.cartridgeBodygroup, profile.cartridgeInserted) end

    self:EmitSound("ambient/machines/keyboard7_clicks_enter.wav", 65, 110)
    return true
end

function ENT:EjectCartridge(ply)
    if not emu.CanManage(ply, self) then
        if IsValid(ply) then ply:ChatPrint("GEMU: Only the owner or current player can eject this cartridge.") end
        return false
    end
    local cart = self:GetInsertedCart()
    if not IsValid(cart) then return end
    emu.ReleaseConsole(self)
    self.EjectCooldown = CurTime() + 1.5

    -- Reset console state
    self:SetHasCartridge(false)
    self.EmuHandoffState = nil
    self:SetInsertedCart(NULL)
    self:SetGameTitle("No Cartridge")
    self:SetRomName("")
    self:SetRomUrl("")
    self:SetCartridgeSkin(0)
    self:SetSkin(0)
    local profile = emu.GetSystem(self)
    if profile.cartridgeBodygroup then self:SetBodygroup(profile.cartridgeBodygroup, profile.cartridgeEmpty) end

    -- Detach and restore cartridge physics
    cart:SetParent(nil)
    cart:SetIsInserted(false)
    cart:SetCurrentConsole(NULL)
    cart.NextInsertTime = CurTime() + 1.5

    local ang = self:GetAngles()
    local yaw = ang.y or ang[2] or 0
    cart:SetAngles(Angle(0, yaw - 90, 0))
    cart:SetMoveType(MOVETYPE_VPHYSICS)
    cart:SetSolid(SOLID_VPHYSICS)
    cart:PhysicsInit(SOLID_VPHYSICS)

    local phys = cart:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(true)
        phys:Wake()
        -- Pop cartridge out with noticeable physical impulse
        phys:ApplyForceCenter((self:GetUp() * 140 - self:GetForward() * 40 + VectorRand() * 5) * phys:GetMass())
    end

    self:EmitSound("weapons/smg1/switch_burst.wav", 75, 120)
    if IsValid(ply) and ply:IsPlayer() then
        ply:ChatPrint("[GEMU] Cartridge ejected.")
    end
end

function ENT:Use(ply, caller, useType, value)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
    if CurTime() < (ply.EmuNextUse or 0) then return end
    if not GetConVar("emu_sv_enabled"):GetBool() then return end
    if not emu.IsNearSetup(ply, self, emu.UseDistance) then return end
    local owner = self:GetControllingPlayer()
    if IsValid(owner) and owner ~= ply and owner.EmuSession ~= self then
        self:SetControllingPlayer(NULL) -- Stale reservation without a running session.
        owner = NULL
    end
    if IsValid(owner) and owner ~= ply then
        if self.GetPlayer2 and self:GetPlayer2() == ply then
            emu.ReleasePlayer2(ply, true)
            return
        end
        if ply:KeyDown(IN_SPEED) then
            local granted, reason = emu.GrantPlayer2(ply, self)
            if not granted then ply:ChatPrint("[GEMU] Cannot join as Player 2: " .. tostring(reason) .. ".") end
            return
        end
        local hint = emu.GetSystem(self).player2 and " Hold sprint and press Use to join as Player 2." or ""
        ply:ChatPrint("[GEMU] Someone is already playing this console." .. hint)
        return
    end

    -- Eject only on explicit Walk+Use or Reload+Use; crouching is ordinary Use.
    if ply:KeyDown(IN_WALK) or ply:KeyDown(IN_RELOAD) then
        if self:GetHasCartridge() then
            self:EjectCartridge(ply)
            return
        end
    end

    -- Normal E: Power on & enter focused play
    if not self:GetPower() then
        self:SetPower(true)
        self:EmitSound("buttons/button14.wav", 60, 100)
    end

    net.Start("emu_open_ui")
    net.WriteEntity(self)
    net.WriteBool(not ply:KeyDown(IN_SPEED))
    net.Send(ply)
end

function ENT:StartTouch(ent)
    if IsValid(ent) and ent.IsEmuCartridge and not ent:GetIsInserted() then
        if ent.NextInsertTime and CurTime() < ent.NextInsertTime then return end
        timer.Simple(0, function()
            if IsValid(self) and IsValid(ent) then
                self:InsertCartridgeEntity(ent)
            end
        end)
    end
end

function ENT:OnRemove()
    emu.ReleaseConsole(self)
    local display = self:GetLinkedDisplay()
    if IsValid(display) then
        display:SetLinkedConsole(NULL)
    end
    local cart = self:GetInsertedCart()
    if IsValid(cart) then
        cart:Remove()
    end
end
