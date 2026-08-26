-- ===================================================
-- SCRIPT DE DIAGNOSTIC & CALIBRATION (PULSE DYNAMIQUE)
-- Fichier : diag.lua
-- ===================================================

local thruster = peripheral.find("creative_vector_thruster")
              or peripheral.find("vector_thruster")
              or peripheral.find("thruster")

local velSensor  = peripheral.find("velocity_sensor")
local gimbSensor = peripheral.find("gimbal_sensor")

term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.yellow)
print("=== CALIBRATION DYNAMIQUE (PULSE 1S) ===")
term.setTextColor(colors.white)

if not thruster or not velSensor or not gimbSensor then
    term.setTextColor(colors.red)
    print("\n[!] Capteurs introuvables.")
    return
end

local angles = gimbSensor.getAngles and gimbSensor.getAngles() or {pitch=0, yaw=0}
local yaw = type(angles) == "table" and (angles.yaw or 0) or 0
print(string.format("Angle Yaw initial : %.2f°", yaw))

print("\nAppuie sur Entree pour lancer le pulse de poussée...")
read()

local function getVelocity()
    local v = velSensor.getVelocity()
    if type(v) == "table" then return v.x or 0, v.z or 0 end
    return 0, 0
end

local function reglerVecteur(vx, vz)
    if thruster.setVector then thruster.setVector(vx, vz)
    else
        if thruster.setVectorX then thruster.setVectorX(vx) end
        if thruster.setVectorY then thruster.setVectorY(vz) end
    end
end

local function reglerPoussee(p)
    if thruster.setPowerNormalized then thruster.setPowerNormalized(p)
    elseif thruster.setThrustNormalized then thruster.setThrustNormalized(p) end
end

print("\n--- PULSE EN COURS ---")
reglerVecteur(0.3, 0.0)
reglerPoussee(1.0)

local maxVx, maxVz = 0, 0

-- Mesure continue pendant 1 seconde
for i = 1, 20 do
    sleep(0.05)
    local vx, vz = getVelocity()
    if math.abs(vx) > math.abs(maxVx) then maxVx = vx end
    if math.abs(vz) > math.abs(maxVz) then maxVz = vz end
end

reglerPoussee(0.0)
reglerVecteur(0.0, 0.0)

term.setTextColor(colors.lime)
print(string.format("\nPoussee X local -> Pic Vitesse Monde : Vx=%.2f | Vz=%.2f", maxVx, maxVz))

print("\n=== DIAGNOSTIC FINAL ===")
term.setTextColor(colors.white)

if math.abs(maxVx) < 0.05 and math.abs(maxVz) < 0.05 then
    term.setTextColor(colors.red)
    print("-> ATTENTION : Aucun mouvement détecté. Le missile est-il bloqué/ancré ?")
elseif math.abs(maxVz) > math.abs(maxVx) then
    print("-> RESULTAT : Les axes sont PERMUTES.")
    print("   Action : Mettre ECHANGER_AXES = true dans testvol.lua")
else
    print("-> RESULTAT : Les axes X/Z sont bien alignes.")
    print("   Action : Mettre ECHANGER_AXES = false dans testvol.lua")
end