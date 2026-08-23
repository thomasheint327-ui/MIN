local modem = peripheral.find("modem")
if modem then
    rednet.open(peripheral.getName(modem))
else
    error("Aucun modem trouve sur ce vehicule !")
end

local monNom = "MISSILE-1" -- Modifie ce nom selon ton engin

print("Telemetrie HAUTE FREQUENCE (Max Hz) activee...")

while true do
    -- On demande la position
    local x, y, z = gps.locate()
    
    if x then
        -- On envoie les données
        rednet.broadcast({
            id = monNom,
            posX = math.floor(x),
            posY = math.floor(y),
            posZ = math.floor(z)
        }, "AEROSPATIAL")
    end
    
    -- 0.05 seconde = 1 tick. C'est la limite physique de Minecraft.
    sleep(0.05)
end