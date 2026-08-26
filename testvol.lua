-- ===================================================
-- LOGICIEL MISSILE - TOP-ATTACK CORRIGE (20 Hz)
-- Fichier : testvol.lua
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

-- ===================================================
-- REGLAGES & REPERES
-- ===================================================
local CANAL_TIR = 1337
local CANAL_TELEMETRIE = 1338
local FACE_EXPLOSIF = "top"
local MAX_TEMPS_VOL = 12

-- Modifie ces booléens si le missile tourne dans le sens opposé à la cible
local INVERSER_X = false
local INVERSER_Z = false

modem.open(CANAL_TIR)

local function reglerPoussee(valeur)
    if thruster.setPowerNormalized then thruster.setPowerNormalized(valeur)
    elseif thruster.setThrustNormalized then thruster.setThrustNormalized(valeur) end
end

local function reglerVecteur(vx, vz)
    if INVERSER_X then vx = -vx end
    if INVERSER_Z then vz = -vz end

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

-- --- MENU D'AMORCAGE ---
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.orange)
print("=== DEMARRAGE SYSTEME MISSILE (CORRIGE) ===")
term.setTextColor(colors.white)
print("1. Mode RUN (Lancement Auto dans 3s)")
print("2. Mode MAINTENANCE (Console Shell)")

local timerId = os.startTimer(3)
local modeMaintenance = false

while true do
    local event, p1 = os.pullEvent()
    if event == "timer" and p1 == timerId then
        break
    elseif event == "char" then
        if p1 == "2" then modeMaintenance = true end
        break
    end
end

if modeMaintenance then
    term.setTextColor(colors.yellow)
    print("\n[!] Passage en Mode MAINTENANCE. Console active.")
    return
end

-- ===================================================
-- BOUCLE INFINIE OPERATIONNELLE (MODE RUN)
-- ===================================================
while true do
    couperPropulsion()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.lime)
    print("=== MISSILE READY (CORRECTION YAW) ===")
    term.setTextColor(colors.white)
    print("Capteurs : Alt=" .. (altSensor and "OK" or "NOK") .. 
          " | Vit=" .. (velSensor and "OK" or "NOK") .. 
          " | Gimbal=" .. (gimbSensor and "OK" or "NOK"))
    term.setTextColor(colors.yellow)
    print("\nEn attente d'un ordre de tir sur CH " .. CANAL_TIR .. "...")

    local cibleX, cibleY, cibleZ
    local ALTITUDE_OFFSET = 35

    while true do
        local _, _, chan, _, message = os.pullEvent("modem_message")
        if chan == CANAL_TIR then
            local data = textutils.unserialize(message)
            if data and data.action == "LANCEMENT" then
                cibleX, cibleY, cibleZ = data.x, data.y, data.z
                ALTITUDE_OFFSET = data.altOffset or 35
                term.setTextColor(colors.green)
                print(string.format("\n[+] Ordre recu ! Cible: X:%.1f Y:%.1f Z:%.1f | Survol: +%dm", cibleX, cibleY, cibleZ, ALTITUDE_OFFSET))
                break
            end
        end
    end

    local startX, startY, startZ = gps.locate(2)
    if startX then
        term.setTextColor(colors.red)
        print("=== VOL ACTIF : GUIDAGE CORRIGE ===")
        
        local startTime = os.clock()
        local DISTANCE_IMPACT = 3.5
        local altCibleCroisiere = math.max(startY, cibleY) + ALTITUDE_OFFSET
        local phaseVol = "MONTEE"
        local currentVecX, currentVecZ = 0.0, 0.0

        reglerPoussee(1.0)

        while true do
            local tempsEcoule = os.clock() - startTime
            local statusActuel = phaseVol

            if tempsEcoule >= MAX_TEMPS_VOL then
                couperPropulsion()
                statusActuel = "ARRET"
            end

            local cx, cy, cz = gps.locate(0.05)
            if altSensor and altSensor.getHeight then
                local altExacte = altSensor.getHeight()
                if altExacte then cy = altExacte end
            end

            if cx then
                local dx, dy, dz = cibleX - cx, cibleY - cy, cibleZ - cz
                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                local dist2D = math.sqrt(dx * dx + dz * dz)

                -- 1. TRANSITION DE PHASE (MONTEE -> PIQUE)
                if phaseVol == "MONTEE" then
                    if cy >= altCibleCroisiere or dist2D < 15 then
                        phaseVol = "PIQUE"
                        statusActuel = "PIQUE"
                    end
                end

                -- 2. VERIFICATION IMPACT
                if dist <= DISTANCE_IMPACT then 
                    statusActuel = "IMPACT" 
                end

                -- 3. TELEMETRIE
                local vx, vz = 0, 0
                if velSensor and velSensor.getVelocity then
                    local v = velSensor.getVelocity()
                    if type(v) == "table" then vx, vz = v.x or 0, v.z or 0 end
                end

                local pitch, yaw = 0, 0
                if gimbSensor and gimbSensor.getAngles then
                    local angles = gimbSensor.getAngles()
                    if type(angles) == "table" then 
                        pitch = angles.pitch or 0 
                        yaw = angles.yaw or 0 
                    end
                end

                modem.transmit(CANAL_TELEMETRIE, CANAL_TIR, textutils.serialize({
                    x = cx, y = cy, z = cz, alt = cy,
                    vit = math.sqrt(vx*vx + vz*vz), pitch = pitch, yaw = yaw,
                    dist = dist, status = statusActuel
                }))

                -- 4. ARRET ET DETONATION
                if statusActuel == "ARRET" then
                    print("[!] TEMPS DE VOL ECOULE.")
                    break
                elseif statusActuel == "IMPACT" then
                    couperPropulsion()
                    redstone.setOutput(FACE_EXPLOSIF, true)
                    print("[+] DETONATION !")
                    break
                end

                -- 5. GUIDAGE PD STABILISE AVEC CORRECTION D'ANGLE YAW
                if phaseVol == "MONTEE" then
                    currentVecX = currentVecX * 0.8
                    currentVecZ = currentVecZ * 0.8
                    reglerVecteur(currentVecX, currentVecZ)
                    reglerPoussee(1.0)
                else
                    -- Phase PIQUE : Erreur amortie par la vitesse
                    local corrX = dx - (vx * 0.6)
                    local corrZ = dz - (vz * 0.6)

                    -- Repère local : alignement trigo avec le yaw Minecraft
                    local radYaw = math.rad(yaw)
                    local localCorrX = corrX * math.cos(radYaw) - corrZ * math.sin(radYaw)
                    local localCorrZ = corrX * math.sin(radYaw) + corrZ * math.cos(radYaw)

                    -- Gain P = 0.03
                    local targetVecX = localCorrX * 0.03
                    local targetVecZ = localCorrZ * 0.03

                    -- Saturation à 30% max de braquage
                    local MAX_BRAQUAGE = 0.3
                    targetVecX = math.max(-MAX_BRAQUAGE, math.min(MAX_BRAQUAGE, targetVecX))
                    targetVecZ = math.max(-MAX_BRAQUAGE, math.min(MAX_BRAQUAGE, targetVecZ))

                    -- Filtre passe-bas (Lissage)
                    currentVecX = currentVecX + (targetVecX - currentVecX) * 0.25
                    currentVecZ = currentVecZ + (targetVecZ - currentVecZ) * 0.25

                    reglerVecteur(currentVecX, currentVecZ)
                    reglerPoussee(1.0)
                end
            end
            sleep(0)
        end
    else
        print("[-] PERTE GPS. Tir avorte.")
    end

    term.setTextColor(colors.gray)
    print("\nReinitialisation du systeme dans 3 secondes...")
    sleep(3)
end