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

local t = radar.getTracks()

local found = 0
for i, track in ipairs(t) do
    if track.category == "CONTRAPTION" then
        found = found + 1
        print("=== CONTRAPTION #" .. found .. " ===")
        print(textutils.serialize(track))
        print("-----------------------------------")
    end
end

if found == 0 then
    print("Aucune cible CONTRAPTION detectee.")
else
    print(found .. " contraption(s) trouvee(s).")
end