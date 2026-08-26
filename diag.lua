-- ===================================================
-- SCRIPT DE DIAGNOSTIC DE VOL & BOÎTE NOIRE COMPLÈTE
-- Fichier : diag.lua
-- Enregistre TOUS les capteurs pendant le vol
-- ===================================================

local modem = peripheral.find("modem", function(_, o) return o.isWireless() end)
local thruster = peripheral.find("creative_vector_thruster")
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
local ALTITUDE_OFFSET = 35

while true do
    local _, _, chan, _, message = os.pullEvent("modem_message")
    if chan == CANAL_TIR then
        local data = textutils.unserialize(message)
        if data and data.action == "LANCEMENT" then
            cibleX, cibleY, cibleZ = data.x, data.y, data.z
            ALTITUDE_OFFSET = data.altOffset or 35
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

-- En-tête CSV avec TOUTES les métriques de TOUS les capteurs
file.writeLine("TEMPS,GPS_X,GPS_Y,GPS_Z,ALT_SENSOR,CAPTEUR_VX,CAPTEUR_VY,CAPTEUR_VZ,CALCUL_VX,CALCUL_VZ,PITCH,YAW,ROLL,TARGET_X,TARGET_Z,PHASE")

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

    -- 3. Lecture Capteur Vitesse Physique
    local captVx, captVy, captVz = 0, 0, 0
    if velSensor and velSensor.getVelocity then
        local v = velSensor.getVelocity()
        if type(v) == "table" then
            captVx = v.x or 0
            captVy = v.y or 0
            captVz = v.z or 0
        end
    end

    -- 4. Calcul de la Vitesse GPS (dérivée mathématique)
    local dt = math.max(0.05, tempsEcoule - lastTime)
    local calcVx, calcVz = 0, 0
    if cx and lastX then
        calcVx = (cx - lastX) / dt
        calcVz = (cz - lastZ) / dt
    end

    -- 5. Lecture Gimbal Sensor (Orientation)
    local pitch, yaw, roll = 0, 0, 0
    if gimbSensor and gimbSensor.getAngles then
        local angles = gimbSensor.getAngles()
        if type(angles) == "table" then
            pitch = angles.pitch or 0
            yaw = angles.yaw or 0
            roll = angles.roll or 0
        end
    end

    -- Mise à jour repères
    if cx then
        lastX, lastZ = cx, cz
    end
    lastTime = tempsEcoule

    -- Arrêt ou Fin de vol
    if phaseVol == "ARRET" then
        couperPropulsion()
        print("\n[!] Temps de vol coule. Propulsion coupee.")
        break
    end

    -- Guidage
    if cx and cy and cz then
        local dx, dy, dz = cibleX - cx, cibleY - cy, cibleZ - cz
        local dist2D = math.sqrt(dx * dx + dz * dz)

        if phaseVol == "MONTEE" and (cy >= altCibleCroisiere or dist2D < 15) then
            phaseVol = "PIQUE"
        end

        if phaseVol == "PIQUE" then
            -- Utilisation de la vitesse capteur si présente, sinon vitesse calculée GPS
            local vxActuelle = (captVx ~= 0) and captVx or calcVx
            local vzActuelle = (captVz ~= 0) and captVz or calcVz

            local corrX = dx - (vxActuelle * 0.6)
            local corrZ = dz - (vzActuelle * 0.6)

            local radYaw = math.rad(yaw)
            local localCorrX = corrX * math.cos(radYaw) - corrZ * math.sin(radYaw)
            local localCorrZ = corrX * math.sin(radYaw) + corrZ * math.cos(radYaw)

            currentVecX = math.max(-0.3, math.min(0.3, localCorrX * 0.03))
            currentVecZ = math.max(-0.3, math.min(0.3, localCorrZ * 0.03))
        end
    end

    reglerVecteur(currentVecX, currentVecZ)
    reglerPoussee(1.0)

    -- 6. Enregistrement dans blackbox.txt
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
print("Transmets-le via : pastebin put blackbox.txt")