-- Cherche et ouvre le modem automatiquement
local modem = peripheral.find("modem")
if modem then
    rednet.open(peripheral.getName(modem))
else
    error("Aucun modem trouve sur ce vehicule !")
end

local monNom = "MISSILE-1" -- Change le nom selon le vaisseau

print("Demarrage de la telemetrie...")

while true do
    -- Le vaisseau demande sa position aux 4 satellites (timeout de 2 secondes)
    local x, y, z = gps.locate(2)
    
    if x then
        -- Si le GPS marche, on prépare un paquet de données
        local donnees = {
            id = monNom,
            posX = math.floor(x),
            posY = math.floor(y),
            posZ = math.floor(z)
        }
        
        -- On envoie les données sur le protocole "AEROSPATIAL"
        rednet.broadcast(donnees, "AEROSPATIAL")
        print("Position envoyee : X:"..donnees.posX.." Y:"..donnees.posY.." Z:"..donnees.posZ)
    else
        print("Erreur : Signal GPS perdu !")
    end
    
    sleep(0.2) -- Mise à jour très rapide (5 fois par seconde)
end