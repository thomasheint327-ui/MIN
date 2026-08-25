-- ===================================================
-- LOGICIEL DE GUIDAGE ET TELEMETRIE EMBARQUEE (20 Hz)
-- Fichier : testvol.lua (ou startup.lua)
-- ===================================================

-- 1. DÉTECTION DIRECTE DES COMPOSANTS
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
local CANAL_TELEMETRIE = 1338
local FACE_EXPLOSIF = "top"

modem.open(CANAL_TIR)

-- Fonctions de pilotage Thruster
local function reglerPoussee(valeur)
    if thruster.setPowerNormalized then
        thruster.setPowerNormalized(valeur)
    elseif thruster.setThrustNormalized then
        thruster.setThrustNormalized(valeur)
    end
end

local function reglerVecteur(vx, vz)
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

-- Statut initial au terminal
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.orange)
print("=== MISSILE OPERATIONNEL (20 Hz) ===")
term.setTextColor(colors.white)
print("Modem sans fil : OK")
print("Vector Thruster: OK")
print("Altimetre      : " .. (altSensor and "OK" or "Absent"))
print("Vitesse Sensor : " .. (velSensor and "OK" or "Absent"))
print("Gimbal Sensor  : " .. (gimbSensor and "OK" or "Absent"))
print("\nEn attente d'ordre sur canal " .. CANAL_TIR .. "...")

-- 2. ATTENTE DE L'ORDRE DE TIR
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

-- 3. VERIFICATION GPS INITIALE
local startX = gps.locate(2)
if not startX then error("[-] GPS introuvable. Annulation.") end
sleep(1)

-- 4. BOUCLE DE VOL & ÉMISSION DE TÉLÉMÉTRIE (20 Hz)
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.red)
print("=== VOL EN COURS - GUIDAGE & TRANSMISSION ===")

local startTime = os.clock()
local MAX_TEMPS_VOL = 5      -- Securite test (5 secondes)
local DISTANCE_IMPACT = 3.5  -- Seuil de mise a feu TNT

reglerPoussee(1.0)

while true do
    local tempsEcoule = os.clock() - startTime
    local statusActuel = "EN VOL"

    if tempsEcoule >= MAX_TEMPS_VOL then
        couperPropulsion()
        statusActuel = "ARRET"
    end

    -- Acquisition GPS + Altitude capteur
    local cx, cy, cz = gps.locate(0.05)
    if altSensor and altSensor.getHeight then
        local altExacte = altSensor.getHeight()
        if altExacte then cy = altExacte end
    end

    if cx then
        local dx = cibleX - cx
        local dy = cibleY - cy
        local dz = cibleZ - cz
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

        -- Vitesse réelle
        local vx, vz = 0, 0
        if velSensor and velSensor.getVelocity then
            local v = velSensor.getVelocity()
            if type(v) == "table" then
                vx = v.x or v[1] or 0
                vz = v.z or v[3] or 0
            end
        end

        -- Orientation Gimbal
        local pitch, yaw = 0, 0
        if gimbSensor and gimbSensor.getAngles then
            local angles = gimbSensor.getAngles()
            if type(angles) == "table" then
                pitch = angles.pitch or angles[1] or 0
                yaw   = angles.yaw   or angles[2] or 0
            end
        end

        -- Verification impact
        if dist <= DISTANCE_IMPACT then
            statusActuel = "IMPACT"
        end

        -- ÉMISSION RADIO TELEMETRIE LIVE VERS VALISE (Canal 1338)
        local telemetryData = textutils.serialize({
            x      = cx,
            y      = cy,
            z      = cz,
            alt    = cy,
            vit    = math.sqrt(vx * vx + vz * vz),
            pitch  = pitch,
            yaw    = yaw,
            dist   = dist,
            status = statusActuel
        })
        modem.transmit(CANAL_TELEMETRIE, CANAL_TIR, telemetryData)

        -- Arret sur coupure temps ou impact
        if statusActuel == "ARRET" then
            term.setCursorPos(1, 9)
            term.setTextColor(colors.red)
            print("\n[!] TEMPS ECOULE - ARRET MOTEUR")
            break
        elseif statusActuel == "IMPACT" then
            couperPropulsion()
            term.setCursorPos(1, 9)
            term.setTextColor(colors.lime)
            print("[+] IMPACT CONFIRME !")
            redstone.setOutput(FACE_EXPLOSIF, true)
            break
        end

        -- GUIDAGE VECTORIEL INERTIEL
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

    sleep(0)
end