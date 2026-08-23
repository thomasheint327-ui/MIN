local monitor = peripheral.find("monitor")
local radar = peripheral.find("create_radar:radar_bearing")

-- Si le radar n'est pas trouvé sous ce nom, on cherche "radar"
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
    print("=== TELEMETRIE RADAR ===")
    print("------------------------")

    -- On récupère les pistes (tracks) avec la bonne fonction
    local ok, tracks = pcall(function() return radar.getTracks() end)

    if ok and tracks then
        if #tracks == 0 then
            monitor.setTextColor(colors.yellow)
            print("\nAucune cible detectee...")
        else
            for i, track in ipairs(tracks) do
                -- On cherche le nom (ex: "TT1" du transponder) ou on affiche le type d'entité (ex: zombie)
                local name = track.name or track.entityType or "Cible Inconnue"
                
                -- Récupération de la position (d'après ta capture d'écran)
                local pos = track.position or {}
                local x = math.floor(pos.x or 0)
                local y = math.floor(pos.y or 0)
                local z = math.floor(pos.z or 0)
                
                -- Nettoyage du nom pour que ce soit plus joli (enlève le "entity.minecraft.")
                name = string.gsub(name, "entity.minecraft.", "")
                name = string.gsub(name, "create:", "")

                -- Couleur différente selon si c'est hostile, animal, ou machine (ton vaisseau)
                if track.category == "HOSTILE" then
                    monitor.setTextColor(colors.red)
                else
                    monitor.setTextColor(colors.cyan)
                end
                
                print(string.format("[%d] %s", i, string.upper(name)))
                
                -- Affichage de l'ID du transponder si on le trouve
                if track.id and type(track.id) == "string" and string.len(track.id) < 15 then
                    monitor.setTextColor(colors.orange)
                    print(string.format("    ID: %s", track.id))
                end

                monitor.setTextColor(colors.white)
                print(string.format("    X:%d Y:%d Z:%d", x, y, z))
            end
        end
    else
        monitor.setTextColor(colors.red)
        print("Erreur de lecture du radar !")
    end

    -- Mise à jour deux fois par seconde (temps réel)
    sleep(0.5)
end