local monitor = peripheral.find("monitor")
local radar = peripheral.find("create_radar:radar_bearing")

if not radar then
    for _, name in ipairs(peripheral.getNames()) do
        if name:find("radar") then
            radar = peripheral.wrap(name)
            break
        end
    end
end

if not monitor then error("Erreur : Aucun ecran trouve sur le reseau !") end
if not radar then error("Erreur : Aucun radar trouve sur le reseau !") end

term.redirect(monitor)
monitor.setTextScale(0.5)

while true do
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    term.setCursorPos(1, 1)

    monitor.setTextColor(colors.green)
    print("=== TELEMETRIE TRANSPONDEURS ===")
    print("--------------------------------")

    local ok, tracks = pcall(function() return radar.getTracks() end)

    if ok and tracks then
        local transponderCount = 0 -- Compte uniquement les vaisseaux détectés

        for _, track in ipairs(tracks) do
            local id = track.id or track.code or ""
            
            -- LE FILTRE MAGIQUE : on ne garde que les entités avec un ID de transpondeur (court)
            if id ~= "" and string.len(id) < 30 then
                transponderCount = transponderCount + 1
                
                local name = track.name or track.entityType or "Inconnu"
                local pos = track.position or {}
                local x = math.floor(pos.x or 0)
                local y = math.floor(pos.y or 0)
                local z = math.floor(pos.z or 0)
                
                name = string.gsub(name, "entity.minecraft.", "")
                name = string.gsub(name, "create:", "")

                monitor.setTextColor(colors.cyan)
                print(string.format("[%d] %s", transponderCount, string.upper(name)))
                
                monitor.setTextColor(colors.orange)
                print(string.format("    [ID]  : %s", id))

                monitor.setTextColor(colors.white)
                print(string.format("    [POS] : X:%d Y:%d Z:%d", x, y, z))
                print("--------------------------------")
            end
        end

        -- Si la boucle s'est terminée sans trouver un seul transpondeur
        if transponderCount == 0 then
            monitor.setTextColor(colors.yellow)
            print("\nAucun transpondeur detecte...")
        end
    else
        monitor.setTextColor(colors.red)
        print("Erreur de lecture du radar !")
    end

    sleep(0.5)
end