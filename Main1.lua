-- ===================================================
-- STATION RADAR — SUIVI DES TRANSPONDEURS
-- ===================================================

-- Détection automatique de l'écran et du radar sur le réseau filaire
local monitor = peripheral.find("monitor")
local radar = peripheral.find("create_radar:radar_bearing")

if not radar then
    for _, name in ipairs(peripheral.getNames()) do
        local ptype = peripheral.getType(name) or ""
        if name:find("radar") or ptype:find("radar") then
            radar = peripheral.wrap(name)
            break
        end
    end
end

if not monitor then error("Erreur : Aucun ecran trouve sur le reseau !") end
if not radar then error("Erreur : Aucun radar trouve sur le reseau !") end

-- Configuration de l'écran
term.redirect(monitor)
monitor.setTextScale(0.5)
monitor.setBackgroundColor(colors.black)

while true do
    monitor.clear()
    term.setCursorPos(1, 1)

    monitor.setTextColor(colors.green)
    print("=== TRANSPONDEURS DETECTES ===")
    print("-------------------------------")

    -- Lecture protégée du radar
    local ok, tracks = pcall(function() return radar.getTracks() end)

    if not ok or not tracks then
        monitor.setTextColor(colors.red)
        print("Erreur lecture radar !")
    else
        local count = 0

        for _, track in ipairs(tracks) do
            local id = track.id or track.code or ""

            -- On ne garde que les entités avec un ID court (transpondeur),
            -- pas les UUID de mobs/joueurs (36 caractères)
            if id ~= "" and #id < 30 then
                count = count + 1

                local name = track.name or track.entityType or "Inconnu"
                name = name:gsub("entity.minecraft.", ""):gsub("create:", "")

                local pos = track.position or {}
                local x = math.floor(pos.x or 0)
                local y = math.floor(pos.y or 0)
                local z = math.floor(pos.z or 0)

                monitor.setTextColor(colors.cyan)
                print(string.format("[%d] %s", count, name:upper()))

                monitor.setTextColor(colors.orange)
                print(string.format("    ID  : %s", id))

                monitor.setTextColor(colors.white)
                print(string.format("    POS : X:%d Y:%d Z:%d", x, y, z))

                monitor.setTextColor(colors.green)
                print("-------------------------------")
            end
        end

        if count == 0 then
            monitor.setTextColor(colors.yellow)
            print("\nAucun transpondeur en vue...")
        end
    end

    sleep(0.5)
end