-- ===================================================
-- SYSTEME DE GUIDAGE MISSILE HAUTE FREQUENCE (20 Hz)
-- ===================================================

-- 1. DETECTION DES PERIPHERIQUES
local modem = peripheral.find("modem", function(_, o) return o.isWireless() end)
local relay = peripheral.find("redstone_relay") or peripheral.wrap("redstone_relay_7")

if not modem then error("[-] Modem sans fil introuvable !") end
if not relay then error("[-] Relais Redstone introuvable !") end

local CANAL_TIR = 1337
modem.open(CANAL_TIR)

-- Fonction pour couper la redstone sur toutes les faces
local function couperMoteurs()
    for _, side in ipairs({"top", "bottom", "left", "right", "front", "back"}) do
        pcall(function() relay.setOutput(side, false) end)
    end
end

couperMoteurs()

term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.orange)
print("=== MISSILE ARME & PRET (20 Hz) ===")
print("En attente de l'ordre de tir sur le canal " .. CANAL_TIR .. "...")

-- 2. RECEPTION DES COORDONNEES CIBLE
local cibleX, cibleY, cibleZ
while true do
    local _, _, chan, _, message = os.pullEvent("modem_message")
    if chan == CANAL_TIR then
        local data = textutils.unserialize(message)
        if data and data.action == "LANCEMENT" then
            cibleX, cibleY, cibleZ = data.x, data.y, data.z
            term.setTextColor(colors.green)
            print("\n[+] Ordre recu ! Cible verrouillee :")
            print(string.format("X: %.1f | Y: %.1f | Z: %.1f", cibleX, cibleY, cibleZ))
            break
        end
    end
end

-- 3. TEST ET VERIFICATION DU SIGNAL GPS
term.setTextColor(colors.yellow)
print("\nAccrochage du signal GPS...")
local startX, startY, startZ
while not startX do
    startX, startY, startZ = gps.locate(1)
    if not startX then
        term.setTextColor(colors.red)
        print("En attente de 4 satellites...")
        sleep(1)
    end
end
term.setTextColor(colors.green)
print("GPS fixe ! Allumage des moteurs dans 2s...")
sleep(2)

-- 4. MISE A FEU ET BOUCLE DE GUIDAGE 20 Hz
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.red)
print("=== VOL EN COURS - GUIDAGE 20 Hz ===")

local startTime = os.clock()
local MAX_TEMPS_VOL = 60    -- Securite temps max (60 secondes)
local DISTANCE_IMPACT = 3.5  -- Distance en blocs pour declencher la fin de vol / impact

-- Allumage de la poussee principale
relay.setOutput("bottom", true)

while true do
    local tempsEcoule = os.clock() - startTime

    -- Securite : Temps de vol maximal atteint
    if tempsEcoule >= MAX_TEMPS_VOL then
        term.setCursorPos(1, 8)
        term.setTextColor(colors.red)
        print("\n[!] Temps de vol max atteint ! Coupure moteurs.")
        couperMoteurs()
        break
    end

    -- Requete GPS ultra-rapide (0.05s / 1 tick Minecraft)
    local cx, cy, cz = gps.locate(0.05)

    if cx then
        -- Calcul du vecteur de trajectoire et de la distance 3D
        local dx = cibleX - cx
        local dy = cibleY - cy
        local dz = cibleZ - cz
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

        -- Telemetrie en temps réel (Mise a jour 20 fois par sec)
        term.setCursorPos(1, 3)
        term.setTextColor(colors.yellow)
        term.clearLine()
        print(string.format("Pos: X:%.1f Y:%.1f Z:%.1f", cx, cy, cz))
        
        term.setCursorPos(1, 4)
        term.setTextColor(colors.cyan)
        term.clearLine()
        print(string.format("Distance Cible : %.1f blocs", dist))
        
        term.setCursorPos(1, 5)
        term.setTextColor(colors.white)
        term.clearLine()
        print(string.format("Temps de vol   : %.1fs", tempsEcoule))

        -- DECISION DE GUIDAGE / ARRET
        if dist <= DISTANCE_IMPACT then
            term.setCursorPos(1, 8)
            term.setTextColor(colors.lime)
            print("[+] CIBLE ATTEINTE ! Impact confirme.")
            couperMoteurs()
            
            -- Signal d'explosion sur la face du haut (si charge explosive connectee)
            relay.setOutput("top", true)
            break
        else
            -- Maintien de la poussée principale
            relay.setOutput("bottom", true)
        end
    else
        -- Signal GPS manque sur 1 tick (affichage d'avertissement fluide sans stagner)
        term.setCursorPos(1, 7)
        term.setTextColor(colors.orange)
        term.clearLine()
        print("[!] GPS : micro-perte de signal (1 tick)")
    end

    -- Pause obligatoire de 1 tick serveur (20 Hz)
    sleep(0)
end

term.setTextColor(colors.gray)
print("\nFin de mission.")