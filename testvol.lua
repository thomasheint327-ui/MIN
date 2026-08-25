-- ===================================================
-- SYSTEME DE GUIDAGE MISSILE AVANCÉ (20 Hz)
-- CONFIGURATION : COMPOSANTS EN CONTACT DIRECT
-- ===================================================

-- 1. DETECTION DE TOUS LES PERIPHERIQUES
local modem = peripheral.find("modem", function(_, o) return o.isWireless() end)
local thruster = peripheral.find("creative_vector_thruster") 
              or peripheral.find("vector_thruster") 
              or peripheral.find("thruster")

local altSensor  = peripheral.find("altitude_sensor")
local velSensor  = peripheral.find("velocity_sensor")
local gimbSensor = peripheral.find("gimbal_sensor")

if not modem then error("[-] Modem sans fil introuvable !") end
if not thruster then error("[-] Vector Thruster introuvable !") end

local CANAL_TIR = 1337
local FACE_EXPLOSIF = "top" -- Face où est posée la TNT
modem.open(CANAL_TIR)

-- Adaptation universelle de l'API Thruster
local function reglerPoussee(valeur) -- 0.0 à 1.0
    if thruster.setPowerNormalized then
        thruster.setPowerNormalized(valeur)
    elseif thruster.setThrustNormalized then
        thruster.setThrustNormalized(valeur)
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

-- Affichage du statut des capteurs au démarrage
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.orange)
print("=== MISSILE GUIDAGE CAPTEURS DIRECTS (20 Hz) ===")
term.setTextColor(colors.white)
print("Modem Sans Fil : OK")
print("Vector Thruster : OK")
print("Altimetre       : " .. (altSensor and "OK (getHeight)" or "Manquant"))
print("Vitesse Sensor  : " .. (velSensor and "OK (getVelocity)" or "Manquant"))
print("Gimbal Sensor   : " .. (gimbSensor and "OK (getAngles)" or "Manquant"))
print("\nEn attente d'ordre sur le canal " .. CANAL_TIR .. "...")

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

-- 3. FIXATION GPS INITIALE
term.setTextColor(colors.yellow)
print("\nFixation du point de depart GPS...")
local startX, startY, startZ = gps.locate(2)
if not startX then error("[-] GPS non accroche. Tir annule.") end
term.setTextColor(colors.green)
print("Position valide ! Allumage moteur dans 1s...")
sleep(1)

-- 4. BOUCLE DE GUIDAGE (20 Hz)
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.red)
print("=== VOL ACTIF - GUIDAGE INERTIEL ET VECTORIEL ===")

local startTime = os.clock()
local MAX_TEMPS_VOL = 5      -- Limite de securite pour test (5 sec)
local DISTANCE_IMPACT = 3.5  -- Seuil de mise a feu TNT

reglerPoussee(1.0)

while true do
    local tempsEcoule = os.clock() - startTime

    if tempsEcoule >= MAX_TEMPS_VOL then
        couperPropulsion()
        term.setCursorPos(1, 10)
        term.setTextColor(colors.red)
        print("\n[!] 5 SECONDES ECOULEES - ARRET PROPVLSION")
        break
    end

    -- 1. Obtenir les coordonnees GPS
    local cx, cy, cz = gps.locate(0.05)

    -- Si l'altimetre est present, on remplace Y par sa mesure ultra-precise
    if altSensor and altSensor.getHeight then
        local altExacte = altSensor.getHeight()
        if altExacte then cy = altExacte end
    end

    if cx then
        local dx = cibleX - cx
        local dy = cibleY - cy
        local dz = cibleZ - cz
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

        -- 2. Obtenir la vitesse réelle pour corriger l'inertie dans les virages
        local vx, vz = 0, 0
        if velSensor and velSensor.getVelocity then
            local v = velSensor.getVelocity()
            if type(v) == "table" then
                vx = v.x or v[1] or 0
                vz = v.z or v[3] or 0
            end
        end

        -- 3. Telemetrie en temps réel
        term.setCursorPos(1, 3)
        term.setTextColor(colors.yellow)
        term.clearLine()
        print(string.format("Pos: X:%.1f Y:%.1f Z:%.1f", cx, cy, cz))

        term.setCursorPos(1, 4)
        term.setTextColor(colors.cyan)
        term.clearLine()
        print(string.format("Dist Cible: %.1f m", dist))

        term.setCursorPos(1, 5)
        term.setTextColor(colors.lime)
        term.clearLine()
        print(string.format("Vitesse   : %.1f m/s", math.sqrt(vx*vx + vz*vz)))

        -- 4. DETECTION IMPACT OU CALCUL CORRECTION VECTORIELLE
        if dist <= DISTANCE_IMPACT then
            couperPropulsion()
            term.setCursorPos(1, 10)
            term.setTextColor(colors.lime)
            print("[+] CIBLE ATTEINTE ! DETONATION ACTIVEE.")
            redstone.setOutput(FACE_EXPLOSIF, true)
            break
        else
            -- Correction d'inertie (Navigation Proportionnelle)
            -- On retranche une partie de la vitesse actuelle pour contrer le dérapage
            local corrX = dx - (vx * 0.4)
            local corrZ = dz - (vz * 0.4)
            local dist2D = math.sqrt(corrX * corrX + corrZ * corrZ)

            if dist2D > 0.1 then
                local vecX = math.max(-1.0, math.min(1.0, corrX / dist2D))
                local vecZ = math.max(-1.0, math.min(1.0, corrZ / dist2D))
                reglerVecteur(vecX, vecZ)
            end

            reglerPoussee(1.0)
        end
    end

    sleep(0)
end

term.setTextColor(colors.gray)
print("\nFin de sequence de tir.")