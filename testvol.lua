-- ===================================================
-- SYSTEME DE GUIDAGE MISSILE HAUTE FREQUENCE (20 Hz)
-- ARCHITECTURE SIMPLIFIEE : VECTOR THRUSTER NATIVE
-- ===================================================

-- 1. DETECTION DES PERIPHERIQUES
local modem = peripheral.find("modem", function(_, o) return o.isWireless() end)
local thruster = peripheral.find("creative_vector_thruster") 
              or peripheral.find("vector_thruster") 
              or peripheral.find("thruster")

if not modem then error("[-] Modem sans fil introuvable !") end
if not thruster then error("[-] Vector Thruster introuvable !") end

local CANAL_TIR = 1337
local FACE_EXPLOSIF = "top" -- Face de l'ordinateur où se trouve la TNT / Détonateur
modem.open(CANAL_TIR)

-- Fonctions d'adaptation natives pour le Thruster
local function reglerPoussee(valeur) -- 0.0 à 1.0
    if thruster.setPowerNormalized then
        thruster.setPowerNormalized(valeur)
    elseif thruster.setThrustNormalized then
        thruster.setThrustNormalized(valeur)
    elseif thruster.setPower then
        thruster.setPower(valeur * 100)
    end
end

local function reglerVecteur(vx, vz) -- -1.0 à 1.0
    if thruster.setVector then
        thruster.setVector(vx, vz)
    else
        if thruster.setVectorX then thruster.setVectorX(vx) end
        if thruster.setVectorY then thruster.setVectorY(vz) end
    end
end

local function couperPropulsion()
    reglerPoussee(0.0)
    reglerVecteur(0.0, 0.0)
    for _, face in ipairs({"top", "bottom", "left", "right", "front", "back"}) do
        redstone.setOutput(face, false)
    end
end

couperPropulsion()

term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.orange)
print("=== MISSILE ARCHITECTURE NETTOYEE (20 Hz) ===")
print("Pilotage vectoriel direct via API Lua")
print("En attente d'ordre sur le canal " .. CANAL_TIR .. "...")

-- 2. RECEPTION DES COORDONNEES CIBLE
local cibleX, cibleY, cibleZ
while true do
    local _, _, chan, _, message = os.pullEvent("modem_message")
    if chan == CANAL_TIR then
        local data = textutils.unserialize(message)
        if data and data.action == "LANCEMENT" then
            cibleX, cibleY, cibleZ = data.x, data.y, data.z
            term.setTextColor(colors.green)
            print(string.format("\n[+] Cible verrouillee : X:%.1f Y:%.1f Z:%.1f", cibleX, cibleY, cibleZ))
            break
        end
    end
end

-- 3. ACCROCHAGE GPS INITIAL
term.setTextColor(colors.yellow)
print("\nAccrochage du signal GPS...")
local startX = gps.locate(2)
if not startX then error("[-] GPS introuvable. Mission avortee.") end
term.setTextColor(colors.green)
print("GPS Fixe ! Mise a feu dans 2s...")
sleep(2)

-- 4. BOUCLE DE VOL 20 Hz (TEST DE 5 SECONDES)
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.red)
print("=== VOL EN COURS - GUIDAGE VECTORIEL ===")

local startTime = os.clock()
local MAX_TEMPS_VOL = 5      -- Vol de test limite a 5s
local DISTANCE_IMPACT = 3.5  -- Seuil de mise a feu en blocs

-- Allumage de la poussée initiale (100 %)
reglerPoussee(1.0)

while true do
    local tempsEcoule = os.clock() - startTime

    -- Sécurité 5 secondes
    if tempsEcoule >= MAX_TEMPS_VOL then
        couperPropulsion()
        term.setCursorPos(1, 9)
        term.setTextColor(colors.red)
        print("\n[!] 5 SECONDES ECOULEES - ARRET MOTEUR")
        break
    end

    -- Requete GPS ultra-rapide 20 Hz (1 tick = 0.05s)
    local cx, cy, cz = gps.locate(0.05)

    if cx then
        local dx = cibleX - cx
        local dy = cibleY - cy
        local dz = cibleZ - cz
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

        -- Telemetrie
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
        print(string.format("Temps de vol   : %.1fs / %.1fs", tempsEcoule, MAX_TEMPS_VOL))

        -- DETECTER IMPACT OU CALCULER DIRECTION
        if dist <= DISTANCE_IMPACT then
            couperPropulsion()
            term.setCursorPos(1, 9)
            term.setTextColor(colors.lime)
            print("[+] CIBLE ATTEINTE ! Activation detonateur.")
            
            -- Activation direct de la Redstone sur l'ordinateur
            redstone.setOutput(FACE_EXPLOSIF, true)
            break
        else
            -- Calcul de l'orientation vectorielle (Axes X et Z)
            local dist2D = math.sqrt(dx * dx + dz * dz)
            if dist2D > 0.1 then
                local vecX = math.max(-1.0, math.min(1.0, dx / dist2D))
                local vecZ = math.max(-1.0, math.min(1.0, dz / dist2D))
                reglerVecteur(vecX, vecZ)
            end
            
            reglerPoussee(1.0)
        end
    else
        term.setCursorPos(1, 7)
        term.setTextColor(colors.orange)
        term.clearLine()
        print("[!] GPS : micro-perte de signal (1 tick)")
    end

    -- Pause 1 tick serveur (20 Hz)
    sleep(0)
end

term.setTextColor(colors.gray)
print("\nFin de mission.")