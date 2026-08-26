-- ===================================================
-- SCRIPT DE DIAGNOSTIC & BOITE NOIRE (diag.lua)
-- ===================================================

local thruster = peripheral.find("creative_vector_thruster")
              or peripheral.find("vector_thruster")
              or peripheral.find("thruster")

local altSensor  = peripheral.find("altitude_sensor")
local velSensor  = peripheral.find("velocity_sensor")
local gimbSensor = peripheral.find("gimbal_sensor")
local modem      = peripheral.find("modem")

term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.yellow)
print("=== DIAGNOSTIC & CALIBRATION MISSILE ===")
term.setTextColor(colors.white)

-- 1. VERIFICATION DES CAPTEURS
print("\n[1/3] VERIFICATION DES PERIPHERIQUES :")
print(" - Thruster : " .. (thruster and "OK" or "MANQUANT"))
print(" - Altitude : " .. (altSensor and "OK" or "MANQUANT"))
print(" - Vitesse  : " .. (velSensor and "OK" or "MANQUANT"))
print(" - Gimbal   : " .. (gimbSensor and "OK" or "MANQUANT"))
print(" - Modem    : " .. (modem and "OK" or "MANQUANT"))

if not thruster or not velSensor or not gimbSensor then
    term.setTextColor(colors.red)
    print("\n[!] Erreur : Capteurs essentiels manquants pour le diagnostic.")
    return
end

-- 2. LECTURE DES ANGLES EN TEMPS REEL
print("\n[2/3] TEST DES CAPTEURS D'ORIENTATION :")
local angles = gimbSensor.getAngles and gimbSensor.getAngles() or {pitch=0, yaw=0}
local pitch = type(angles) == "table" and (angles.pitch or 0) or 0
local yaw   = type(angles) == "table" and (angles.yaw or 0) or 0
print(string.format(" Angle Pitch : %.2f°", pitch))
print(string.format(" Angle Yaw   : %.2f°", yaw))

-- 3. TEST DE CALIBRATION DU THRUSTER
print("\n[3/3] TEST DE CALIBRATION DU THRUSTER")
print("Pose le missile sur un espace degage.")
print("Appuie sur Entree pour lancer le test de poussee (1 seconde)...")
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

print("\n--- TEST EN COURS ---")
-- Test de poussée sur X local
reglerVecteur(0.3, 0.0)
reglerPoussee(1.0)
sleep(0.5)
local vx_res, vz_res = getVelocity()
reglerPoussee(0.0)
reglerVecteur(0.0, 0.0)

print(string.format("Poussee X local -> Vitesse Monde : Vx=%.2f | Vz=%.2f", vx_res, vz_res))

-- ANALYSE DES RESULTATS
term.setTextColor(colors.lime)
print("\n=== DIAGNOSTIC FINAL ===")
term.setTextColor(colors.white)

if math.abs(vz_res) > math.abs(vx_res) then
    print("-> RESULTAT : Les axes sont PERMUTES.")
    print("   Action : Mettre ECHANGER_AXES = true dans testvol.lua")
else
    print("-> RESULTAT : Les axes X/Z sont bien alignes.")
    print("   Action : Mettre ECHANGER_AXES = false dans testvol.lua")
end

if (math.abs(vx_res) > math.abs(vz_res) and vx_res < 0) or (math.abs(vz_res) > math.abs(vx_res) and vz_res < 0) then
    print("-> RESULTAT : L'axe principal est INVERSE.")
    print("   Action : Inverser le signe de INVERSER_X ou INVERSER_Z")
end

-- GENERATION DU FICHER BLACKBOX DUMMY
local file = fs.open("blackbox.txt", "w")
file.writeLine("TIMESTAMP,YAW,PITCH,VX_LOCAL,VZ_LOCAL")
file.writeLine(string.format("%f,%f,%f,%f,%f", os.clock(), yaw, pitch, vx_res, vz_res))
file.close()
print("\nFichier 'blackbox.txt' cree avec succes.")