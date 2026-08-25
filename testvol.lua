-- ===================================================
-- LOGICIEL MISSILE - RUN AUTO & MAINTENANCE (20 Hz)
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

local CANAL_TIR = 1337
local CANAL_TELEMETRIE = 1338
local FACE_EXPLOSIF = "top"
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

-- --- MENU D'AMORCAGE (RUN / MAINTENANCE) ---
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.orange)
print("=== DEMARRAGE SYSTEME MISSILE ===")
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
    print("=== MISSILE READY (MODE RUN) ===")
    term.setTextColor(colors.white)
    print("Capteurs : Alt=" .. (altSensor and "OK" or "NOK") .. 
          " | Vit=" .. (velSensor and "OK" or "NOK") .. 
          " | Gimbal=" .. (gimbSensor and "OK" or "NOK"))
    term.setTextColor(colors.yellow)
    print("\nEn attente d'un ordre de tir sur CH " .. CANAL_TIR .. "...")

    -- Attente de l'ordre de tir
    local cibleX, cibleY, cibleZ
    while true do
        local _, _, chan, _, message = os.pullEvent("modem_message")
        if chan == CANAL_TIR then
            local data = textutils.unserialize(message)
            if data and data.action == "LANCEMENT" then
                cibleX, cibleY, cibleZ = data.x, data.y, data.z
                term.setTextColor(colors.green)
                print(string.format("\n[+] Ordre recu ! Cible: X:%.1f Y:%.1f Z:%.1f", cibleX, cibleY, cibleZ))
                break
            end
        end
    end

    -- Accrochage GPS
    local startX = gps.locate(2)
    if startX then
        term.setTextColor(colors.red)
        print("=== VOL ACTIF (20 Hz) ===")
        
        local startTime = os.clock()
        local MAX_TEMPS_VOL = 5
        local DISTANCE_IMPACT = 3.5

        reglerPoussee(1.0)

        while true do
            local tempsEcoule = os.clock() - startTime
            local statusActuel = "EN VOL"

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

                local vx, vz = 0, 0
                if velSensor and velSensor.getVelocity then
                    local v = velSensor.getVelocity()
                    if type(v) == "table" then vx, vz = v.x or 0, v.z or 0 end
                end

                local pitch, yaw = 0, 0
                if gimbSensor and gimbSensor.getAngles then
                    local angles = gimbSensor.getAngles()
                    if type(angles) == "table" then pitch, yaw = angles.pitch or 0, angles.yaw or 0 end
                end

                if dist <= DISTANCE_IMPACT then statusActuel = "IMPACT" end

                -- Envoi Telemetrie
                modem.transmit(CANAL_TELEMETRIE, CANAL_TIR, textutils.serialize({
                    x = cx, y = cy, z = cz, alt = cy,
                    vit = math.sqrt(vx*vx + vz*vz), pitch = pitch, yaw = yaw,
                    dist = dist, status = statusActuel
                }))

                if statusActuel == "ARRET" then
                    print("[!] FIN DU TEMPS DE VOL.")
                    break
                elseif statusActuel == "IMPACT" then
                    couperPropulsion()
                    redstone.setOutput(FACE_EXPLOSIF, true)
                    print("[+] DETONATION !")
                    break
                end

                -- Guidage
                local corrX, corrZ = dx - (vx * 0.4), dz - (vz * 0.4)
                local dist2D = math.sqrt(corrX * corrX + corrZ * corrZ)
                if dist2D > 0.1 then
                    reglerVecteur(math.max(-1.0, math.min(1.0, corrX / dist2D)), math.max(-1.0, math.min(1.0, corrZ / dist2D)))
                end
                reglerPoussee(1.0)
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