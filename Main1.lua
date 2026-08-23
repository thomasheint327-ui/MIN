-- Connexion directe aux périphériques détectés
local monitor = peripheral.wrap("monitor_3") or peripheral.find("monitor")
local radar = peripheral.wrap("radar_bearing_0") 
          or peripheral.find("create_radar_bearing") 
          or peripheral.find("radar")

if not monitor then error("Erreur : monitor_3 introuvable !") end
if not radar then error("Erreur : radar_bearing_0 introuvable !") end

-- Redirection de l'affichage vers l'écran
term.redirect(monitor)
monitor.setTextScale(0.5)
monitor.setBackgroundColor(colors.black)
monitor.setTextColor(colors.green)

while true do
    monitor.clear()
    term.setCursorPos(1, 1)
    
    print("=== TELEMETRIE RADAR ===")
    print("------------------------")

    -- Récupération des cibles
    local targets = {}
    if radar.getDetectedTargets then
        targets = radar.getDetectedTargets()
    elseif radar.getEntities then
        targets = radar.getEntities()
    elseif radar.scan then
        targets = radar.scan()
    end

    if not targets or #targets == 0 then
        monitor.setTextColor(colors.yellow)
        print("\nAucune cible detectee...")
        monitor.setTextColor(colors.green)
    else
        for i, target in ipairs(targets) do
            local name = target.name or target.type or ("Cible #" .. i)
            local pos = target.position or target
            local x = math.floor(pos.x or pos.posX or 0)
            local y = math.floor(pos.y or pos.posY or 0)
            local z = math.floor(pos.z or pos.posZ or 0)
            
            monitor.setTextColor(colors.white)
            print(string.format("[%d] %s", i, name))
            
            monitor.setTextColor(colors.lightGray)
            print(string.format("    X:%d Y:%d Z:%d", x, y, z))
        end
    end
    
    sleep(0.5)
end