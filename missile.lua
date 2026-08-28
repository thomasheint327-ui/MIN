-- Test unitaire d'orientation des ailerons en croix
local pitch_name = "aileron_bearing_6"
local yaw_name   = "aileron_bearing_7"

local aileron_pitch = peripheral.wrap(pitch_name)
local aileron_yaw   = peripheral.wrap(yaw_name)

if not aileron_pitch then error("Erreur : " .. pitch_name .. " introuvable !") end
if not aileron_yaw then error("Erreur : " .. yaw_name .. " introuvable !") end

term.clear()
term.setCursorPos(1, 1)
print("========================================")
print("      TEST UNITAIRE DES AILERONS        ")
print("========================================")

-- 1. Test du premier aileron (Aileron 6)
print("\n[1/3] Orientation de " .. pitch_name .. " à +30°...")
aileron_pitch.setHeadAngle("primary", 30)
sleep(2)

-- 2. Test du second aileron (Aileron 7)
print("[2/3] Orientation de " .. yaw_name .. " à +30°...")
aileron_yaw.setHeadAngle("primary", 30)
sleep(2)

-- 3. Remise au neutre
print("[3/3] Remise à 0° des deux ailerons...")
aileron_pitch.setHeadAngle("primary", 0)
aileron_yaw.setHeadAngle("primary", 0)

print("\n[FIN] Test unitaire terminé avec succès.")
