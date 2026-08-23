local radar = peripheral.find("create_radar:radar_bearing")
if not radar then
    for _, name in ipairs(peripheral.getNames()) do
        if name:find("radar") then
            radar = peripheral.wrap(name)
            break
        end
    end
end

if not radar then
    error("Aucun radar trouve !")
end

print("=== METHODES DISPONIBLES SUR LE RADAR ===")
for _, method in ipairs(peripheral.getMethods(peripheral.getName(radar))) do
    print(" - " .. method)
end