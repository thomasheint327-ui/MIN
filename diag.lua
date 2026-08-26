-- ===================================================
-- SCRIPT DE DIAGNOSTIC DE VOL & BOÎTE NOIRE COMPLÈTE
-- Fichier : diag.lua (Corrigé & Calibré)
-- ===================================================

local modem     = peripheral.find("modem", function(_, o) return o.isWireless() end)
local thruster  = peripheral.find("creative_vector_thruster")
               or peripheral.find("vector_thruster")
               or peripheral.find("thruster")

local altSensor  = peripheral.find("altitude_sensor")
local velSensor  = peripheral.find("velocity_sensor")
local gimbSensor = peripheral.find("gimbal_sensor")

if not modem or not thruster then
    error("[-] Composants critiques introuvables (Modem/Thruster)")
end

local CANAL_TIR = 1337
modem.open(CANAL_TIR)

-- ===================================================
-- PARAMÈTRES DE CALIBRATION DU GUIDAGE (À AJUSTER)
-- ===================================================
local GAIN_ANTICIPATION = 0.6  -- Secondes d'avance pour prédire la position future
local GAIN_CORRECTION   = 0.03 -- Force de braquage (plus haut = plus agressif)
local MAX_VECTOR_ANGLE  = 0.3  -- Inclinaison max de la tuyère (-0.3 à +0.3)
local ALTITUDE_OFFSET   = 35   -- Altitude de croisière au-dessus du point de départ

local function reglerPoussee(valeur)
    if thruster.setPowerNormalized then thruster.setPowerNormalized(valeur)
    elseif thruster.setThrustNormalized then thruster.setThrustNormalized(valeur) end
end

local function reglerVecteur(vx, vz)
    if thruster.setVector then thruster.setVector(vx, vz)
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

term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.yellow)
print("=== DIAGNOSTIC DE VOL & BOITE NOIRE COMPLETE ===")
term.setTextColor(colors.white)

print("\n--- ETAT DES CAPTEURS DETECTES ---")
print(" Modems/Radio : " .. (modem and "OK" or "NOK"))
print(" Thruster     : " .. (thruster and "OK" or "NOK"))
print(" Altitude     : " .. (altSensor and "OK" or "NOK"))
print(" Vitesse      : " .. (velSensor and "OK" or "NOK"))
print(" Gimbal       : " .. (gimbSensor and "OK" or "NOK"))

local startX, startY, startZ = gps.locate(2)
print(" Signal GPS   : " .. (startX and string.format("OK (X:%.1f Y:%.1f Z:%.1f)", startX, startY, startZ) or "NOK (Pas de GPS)"))

print("\n----------------------------------------")
print("En attente d'un ordre de tir sur canal " .. CANAL_TIR .. "...")
print("Le vol sera enregistre dans 'blackbox.txt'.")

local cibleX, cibleY, cibleZ

while true do
    local _, _, chan, _, message = os.pullEvent("modem_message")
    if chan == CANAL_TIR then
        local data = textutils.unserialize(message)
        if data and data.action == "LANCEMENT" then
            cibleX, cibleY, cibleZ = data.x, data.y, data.z
            ALTITUDE_OFFSET = data.altOffset or ALTITUDE_OFFSET
            term.setTextColor(colors.lime)
            print(string.format("\n[+] Cible recue : X:%.1f Y:%.1f Z:%.1f", cibleX, cibleY, cibleZ))
            break
        end
    end
end

-- Ouverture du fichier de log
local file = fs.open("blackbox.txt", "w")
if not file then
    error("[-] Impossible de creer blackbox.txt")
end

-- En-tête CSV
file.writeLine("TEMPS,GPS_X,GPS_Y,GPS_Z,ALT_SENSOR,CAPTEUR_VX,CAPTEUR_VY,CAPTEUR_VZ,CALCUL_VX,CALCUL_VZ,PITCH,YAW,ROLL,VEC_X,VEC_Z,PHASE")

term.setTextColor(colors.red)
print("\n=== DECOLLAGE & ENREGISTREMENT DE VOL EN COURS ===")

local startTime = os.clock()
local MAX_TEMPS_VOL = 12
local phaseVol = "MONTEE"

local lastX, lastZ, lastTime = nil, nil, 0
local altCibleCroisiere = (startY or 70) + ALTITUDE_OFFSET
local currentVecX, currentVecZ = 0.0, 0.0

reglerPoussee(1.0)

while true do
    local now = os.clock()
    local tempsEcoule = now - startTime

    if tempsEcoule >= MAX_TEMPS_VOL then
        phaseVol = "ARRET"
    end

    -- 1. Lecture GPS
    local cx, cy, cz = gps.locate(0.05)

    -- 2. Lecture Capteur Altitude
    local altVal = "N/A"
    if altSensor and altSensor.getHeight then
        local a = altSensor.getHeight()
        if a then altVal = tostring(a) end
    end

    -- 3. Lecture Capteur Vitesse Physique (CORRIGÉ : lecture directe du tuple)
    local captVx, captVy, captVz = 0, 0, 0
    if velSensor and velSensor.getVelocity then
        local x, y, z = velSensor.getVelocity()
        captVx = x or 0
        captVy = y or 0
        captVz = z or 0
    end

    -- 4. Calcul de la Vitesse GPS (dérivée)
    local dt = math.max(0.05, tempsEcoule - lastTime)
    local calcVx, calcVz = 0, 0
    if cx and lastX then
        calcVx = (cx - lastX) / dt
        calcVz = (cz - lastZ) / dt
    end

    -- 5. Lecture Gimbal Sensor (Orientation)
    local pitch, yaw, roll = 0, 0, 0
    if gimbSensor then
        if gimbSensor.getAngles then
            local res1, res2, res3 = gimbSensor.getAngles()
            if type(res1) == "table" then
                pitch, yaw, roll = res1.pitch or 0, res1.yaw or 0, res1.roll or 0
            else
                pitch, yaw, roll = res1 or 0, res2 or 0, res3 or 0
            end
        end
    end

    -- Mise à jour repères
    if cx then
        lastX, lastZ = cx, cz
    end
    lastTime = tempsEcoule

    -- Arrêt du vol
    if phaseVol == "ARRET" then
        couperPropulsion()
        print("\n[!] Temps de vol coule. Propulsion coupee.")
        break
    end

    -- GUIDAGE PARABOLIQUE & ANTICIPATION
    if cx and cy and cz then
        local dx, dy, dz = cibleX - cx, cibleY - cy, cibleZ - cz
        local dist2D = math.sqrt(dx * dx + dz * dz)

        if phaseVol == "MONTEE" and (cy >= altCibleCroisiere or dist2D < 15) then
            phaseVol = "PIQUE"
        end

        if phaseVol == "PIQUE" then
            -- On utilise en priorité la vitesse réelle du capteur, sinon celle du GPS
            local vxActuelle = (captVx ~= 0) and captVx or calcVx
            local vzActuelle = (captVz ~= 0) and captVz or calcVz

            -- Anticipation de la trajectoire
            local corrX = dx - (vxActuelle * GAIN_ANTICIPATION)
            local corrZ = dz - (vzActuelle * GAIN_ANTICIPATION)

            -- Conversion repère Monde -> repère local du missile via Gimbal Yaw
            local radYaw = math.rad(yaw)
            local localCorrX = corrX * math.cos(radYaw) - corrZ * math.sin(radYaw)
            local localCorrZ = corrX * math.sin(radYaw) + corrZ * math.cos(radYaw)

            currentVecX = math.max(-MAX_VECTOR_ANGLE, math.min(MAX_VECTOR_ANGLE, localCorrX * GAIN_CORRECTION))
            currentVecZ = math.max(-MAX_VECTOR_ANGLE, math.min(MAX_VECTOR_ANGLE, localCorrZ * GAIN_CORRECTION))
        end
    end

    reglerVecteur(currentVecX, currentVecZ)
    reglerPoussee(1.0)

    -- 6. Écriture dans la boîte noire (CSV)
    file.writeLine(string.format(
        "%.2f,%.2f,%.2f,%.2f,%s,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%s",
        tempsEcoule,
        cx or 0, cy or 0, cz or 0,
        altVal,
        captVx, captVy, captVz,
        calcVx, calcVz,
        pitch, yaw, roll,
        currentVecX, currentVecZ,
        phaseVol
    ))
    file.flush()

    sleep(0)
end

file.close()

term.setTextColor(colors.lime)
print("\n[+] Enregistrement termine !")
print("Fichier 'blackbox.txt' genere.")