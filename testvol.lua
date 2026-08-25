local modem = peripheral.find("modem")
if not modem then error("Modem requis sur le missile !") end

local CANAL_TIR = 1337
modem.open(CANAL_TIR)

local function couperMoteurs()
    for _, face in ipairs(rs.getSides()) do
        rs.setAnalogOutput(face, 0)
    end
end

couperMoteurs()
term.clear()
term.setCursorPos(1,1)
term.setTextColor(colors.orange)
print("=== MISSILE ARME & PRET ===")
print("En attente de l'ordre de tir...")

local cibleX, cibleY, cibleZ

-- 1. ATTENTE DU SIGNAL RADIO
while true do
    local event, side, chan, repChan, message = os.pullEvent("modem_message")
    if chan == CANAL_TIR then
        -- On décode le paquet reçu
        local data = textutils.unserialize(message)
        if data and data.action == "LANCEMENT" then
            cibleX = data.x
            cibleY = data.y
            cibleZ = data.z
            term.setTextColor(colors.green)
            print("\n[+] Cible verrouillee :")
            print("X:"..cibleX.." Y:"..cibleY.." Z:"..cibleZ)
            break
        end
    end
end

-- 2. ACQUISITION DU GPS (Ne plante plus s'il n'y a pas de signal)
term.setTextColor(colors.yellow)
print("\nRecherche des satellites GPS...")
local startX, startY, startZ

while true do
    startX, startY, startZ = gps.locate(2)
    if startX then
        term.setTextColor(colors.green)
        print("Signal GPS acquis !")
        break
    else
        term.setTextColor(colors.red)
        print("Echec GPS. Nouvelle tentative...")
        sleep(2) -- Attend 2 secondes et réessaie au lieu de crasher
    end
end

-- 3. MISE A FEU (Test de 4 secondes)
term.setTextColor(colors.red)
print("\nMISE A FEU DANS 3 SECONDES !")
sleep(3) -- Laisse le temps de reculer si tu es à côté du missile

local startTime = os.clock()

while true do
    local tempsEcoule = os.clock() - startTime
    
    if tempsEcoule >= 4 then
        term.setTextColor(colors.red)
        print("\n[!] 4 SECONDES - COUPURE MOTEURS [!]")
        couperMoteurs()
        break
    end

    local cx, cy, cz = gps.locate(1)
    
    if cx then
        term.setCursorPos(1, 14)
        term.setTextColor(colors.white)
        print("Temps de vol : " .. string.format("%.1f", tempsEcoule) .. "s / 4.0s  ")
        
        -- Propulseur principal (Marche avant)
        rs.setAnalogOutput("back", 15) 
        
        -- Gestion altitude
        local dy = cibleY - cy
        if dy > 2 then
            rs.setAnalogOutput("bottom", 15)
        else
            rs.setAnalogOutput("bottom", 0)
        end
    end
    sleep(0.1)
end