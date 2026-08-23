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

print("Total cibles detectees : " .. #t)
print("---------------------------------------")

local found = 0
for i, track in ipairs(t) do
    if track.name ~= nil then
        found = found + 1
        print(i .. " NAME:" .. tostring(track.name) .. " CAT:" .. tostring(track.category) .. " ID:" .. tostring(track.id))
    end
end

if found == 0 then
    print("Aucune cible avec un champ 'name' rempli.")
    print("---------------------------------------")
    print("Categories rencontrees dans la liste :")
    local cats = {}
    for _, track in ipairs(t) do
        cats[tostring(track.category)] = true
    end
    for c in pairs(cats) do
        print(" - " .. c)
    end
else
    print("---------------------------------------")
    print(found .. " cible(s) nommee(s) trouvee(s).")
end