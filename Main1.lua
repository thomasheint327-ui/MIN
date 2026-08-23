-- Détection automatique sur le réseau filaire
local monitor = peripheral.find("monitor")
local radar = peripheral.find("create_radar:radar_bearing")

-- Recherche poussée si peripheral.find n'a pas capturé le mod
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

-- Redirection vers l'écran
term.redirect(monitor)
local w, h = monitor.getSize()
monitor.setTextScale(0.5)
monitor.setBackgroundColor(colors.black)
monitor.setTextColor(colors.green)

while true do
    monitor.clear()
    term.setCursorPos(1, 1)

    print("=== TELEMETRIE RADAR ===")
    print("------------------------")

    -- Récupération des cibles (protégée par pcall)
    local targets = {}
    local ok, result = pcall(function()
        if radar.getDetectedTargets then
            return radar.getDetectedTargets()
        elseif radar.getEntities then
            return radar.getEntities()
        elseif radar.scan then
            return radar.scan()
        end
        return {}
    end)

    if ok and result then
        targets = result
    else
        monitor.setTextColor(colors.red)
        print("Erreur lecture radar !")
        monitor.setTextColor(colors.green)
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