-- =======================================
-- SYSTEME DE VOL MISSILE (TEST 4 SECONDES)
-- =======================================

-- Detection automatique des peripheriques (Modem sans fil + Relais Redstone)
local modem = peripheral.find("modem", function(name, o) return o.isWireless() end)
local relay = peripheral.find("redstone_relay") or peripheral.wrap("redstone_relay_7")

if not modem then error("Erreur: Modem sans fil introuvable sur le missile !") end
if not relay then error("Erreur: Relais Redstone introuvable sous le modem !") end

local CANAL_TIR = 1337
modem.open(CANAL_TIR)

-- Fonction de securite d'arret d'urgence
local function couperMoteurs()
    for _, side in ipairs({"top", "bottom", "left", "right", "front", "back"}) do
        pcall(function() relay.setOutput(side, false) end)
    end
end

couperMoteurs()

term.clear()
term.setCursorPos(1,1)
term.setTextColor(colors.orange)
print("=== MISSILE ARME & PRET ===")
print("En attente de l'ordre de tir...")

local cibleX, cibleY, cibleZ

-- 1. ATTENTE DU SIGNAL RADIO DU POCKET COMPUTER
while true do
    local event, side, chan, repChan, message = os.pullEvent("modem_message")
    if chan == CANAL_TIR then
        local data = textutils.unserialize(message)
        if data and data.action == "LANCEMENT" then
            cibleX = data.x
            cibleY = data.y
            cibleZ = data.z
            term.setTextColor(colors.green)
            print("\n[+] Order recu ! Cible verrouillee :")
            print("X: " .. cibleX .. " | Y: " .. cibleY .. " | Z: " .. cibleZ)
            break
        end
    end
end

-- 2. ACQUISITION DU GPS
term.setTextColor(colors.yellow)
print("\nRecherche du signal GPS...")
local startX, startY, startZ

while true do
    startX, startY, startZ = gps.locate(2)
    if startX then
        term.setTextColor(colors.green)
        print("Signal GPS fixe avec succes !")
        break
    else
        term.setTextColor(colors.red)
        print("Recherche GPS en cours...")
        sleep(2)
    end
end

-- 3. CHRONO & MISE A FEU (LIMITEE A 4 SECONDES)
term.setTextColor(colors.red)
print("\n[!] ALLUMAGE MOTEUR DANS 3 SECONDES [!]")
sleep(3)

local startTime = os.clock()

while true do
    local tempsEcoule = os.clock() - startTime
    
    -- SECURITE DE 4 SECONDES
    if tempsEcoule >= 4 then
        term.setTextColor(colors.red)
        print("\n[!] 4 SECONDES ECOULEES - COUPURE MOTEUR [!]")
        couperMoteurs()
        break
    end

    local cx, cy, cz = gps.locate(1)
    
    if cx then
        term.setCursorPos(1, 14)
        term.setTextColor(colors.white)
        print("Temps de vol : " .. string.format("%.1f", tempsEcoule) .. "s / 4.0s  ")
        
        -- Allumage du moteur vers le bas via le relais
        relay.setOutput("bottom", true)
    end
    
    sleep(0.1)
end

term.setTextColor(colors.gray)
print("\nFin du vol d'essai. Recuperation du prototype.")