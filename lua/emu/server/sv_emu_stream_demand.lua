-- Upload video only while another player is near this particular entity.
if not SERVER then return end
util.AddNetworkString("emu_video_demand")
local nextUpdate = 0
hook.Add("Think", "Emu_UpdateVideoDemand", function()
    if CurTime() < nextUpdate then return end
    nextUpdate = CurTime() + 0.5
    if SetGlobalBool then SetGlobalBool("EmuStreamReliable", emu.StreamReliable()) end
    for _, ply in ipairs(player.GetAll()) do
        -- Capture follows the running session, not input focus.
        local target = ply.EmuSession
        local wanted = IsValid(target) and emu.IsSessionRunner(ply, target)
            and #(emu.GetFallbackRecipients or emu.GetVideoRecipients)(ply, target) > 0 or false
        if target ~= ply.EmuVideoDemandTarget or wanted ~= ply.EmuVideoDemand then
            -- Explicitly stop the old target if the player changes devices.
            if IsValid(ply.EmuVideoDemandTarget) and ply.EmuVideoDemandTarget ~= target then
                net.Start("emu_video_demand") net.WriteEntity(ply.EmuVideoDemandTarget) net.WriteBool(false) net.Send(ply)
            end
            if IsValid(target) then
                net.Start("emu_video_demand") net.WriteEntity(target) net.WriteBool(wanted) net.Send(ply)
            end
            ply.EmuVideoDemandTarget, ply.EmuVideoDemand = target, wanted
        end
    end
end)
