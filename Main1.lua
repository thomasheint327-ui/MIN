-- Détection des périphériques
local monitor = peripheral.find("monitor")
local radar = peripheral.find("create_radar_bearing") 
          or peripheral.find("radar") 
          or peripheral.find("advanced_radar")

if not monitor then error("Erreur : Aucun écran détecté !") end
if not radar then error("Erreur : Aucun radar détecté !") end

-- Redirection de l'affichage vers l'écran
term.redirect(monitor)
monitor.setTextScale(0.5)

while true do
    term.clear()
    term.setCursorPos(1, 1)
    
    print("=== TELEMETRIE RADAR ===")
    print("")

    -- Récupération des cibles
    local targets = {}
    if radar.getDetectedTargets then
        targets = radar.getDetectedTargets()
    elseif radar.getEntities then
        targets = radar.getEntities()
    elseif radar.scan then
        targets = radar.scan()
    end

    if #targets == 0 then
        print("Aucune cible détectée...")
    else
        for i, target in ipairs(targets) do
            local name = target.name or target.type or ("Cible #" .. i)
            local x = math.floor(target.x or target.posX or 0)
            local y = math.floor(target.y or target.posY or 0)
            local z = math.floor(target.z or target.posZ or 0)
            
            print(string.format("[%d] %s", i, name))
            print(string.format("    X:%d Y:%d Z:%d", x, y, z))
        end
    end
    
    sleep(0.5)
end