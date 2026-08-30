-- ============================================================================
-- MISSILE.LUA - BANC DE TEST SÉQUENTIEL DES PÉRIPHÉRIQUES
-- ============================================================================

local function log(step, msg)
    print(string.format("[%s] %s", step, msg))
    sleep(0.8)
end

local function safe_call(obj, func_names, ...)
    if not obj then return false end
    for _, fn in ipairs(func_names) do
        if type(obj[fn]) == "function" then
            local ok, err = pcall(obj[fn], ...)
            if ok then return true end
        end
    end
    return false
end

term.clear()
term.setCursorPos(1, 1)
print("========================================")
print("  BANC DE TEST SÉQUENTIEL GLOBAL")
print("========================================")
sleep(1)

-------------------------------------------------------------------------------
-- 1. TEST DES CAPTEURS (LECTURE REPETEE 2 SECONDES)
-------------------------------------------------------------------------------
print("\n--- 1. TEST DES CAPTEURS ---")

-- Altitude
local alt_sensor = peripheral.find("altitude_sensor")
if alt_sensor then
    local alt = 0
    safe_call(alt_sensor, {"getAltitude"}, function(v) alt = v end)
    log("ALTITUDE", string.format("Altitude lue : %.2f m", alt))
else
    log("ALTITUDE", "Non detecte !")
end

-- Gimbal (Angles)
local gimbal = peripheral.find("gimbal_sensor")
if gimbal then
    local p, y, r = 0, 0, 0
    if gimbal.getAngles then
        local a = gimbal.getAngles()
        if type(a) == "table" then p, y, r = a[1] or 0, a[2] or 0, a[3] or 0 end
    end
    log("GIMBAL", string.format("P: %.1f | Y: %.1f | R: %.1f", p, y, r))
else
    log("GIMBAL", "Non detecte !")
end

-- Velocite
local vel_sensors = { peripheral.find("velocity_sensor") }
log("VELOCITY", string.format("%d capteur(s) de vitesse trouve(s)", #vel_sensors))

-------------------------------------------------------------------------------
-- 2. TEST MOTEUR CREATIVE (ACCEL / DECEL)
-------------------------------------------------------------------------------
print("\n--- 2. TEST MOTEUR (CREATIVE MOTOR) ---")
local motor = peripheral.find("Create_CreativeMotor")

if motor then
    log("MOTEUR", "Acceleration a +64 RPM...")
    safe_call(motor, {"setGeneratedSpeed", "setTargetSpeed"}, 64)
    sleep(1.5)
    
    log("MOTEUR", "Inversion a -64 RPM...")
    safe_call(motor, {"setGeneratedSpeed", "setTargetSpeed"}, -64)
    sleep(1.5)
    
    log("MOTEUR", "Arret (0 RPM)...")
    safe_call(motor, {"setGeneratedSpeed", "setTargetSpeed"}, 0)
else
    log("MOTEUR", "Non detecte !")
end

-------------------------------------------------------------------------------
-- 3. TEST INDIVIDUEL DES AILERONS
-------------------------------------------------------------------------------
print("\n--- 3. TEST DES AILERONS ---")
local ailerons = { peripheral.find("aileron_bearing") }

log("AILERONS", string.format("%d aileron(s) trouve(s)", #ailerons))

for i, ail in ipairs(ailerons) do
    log("AILERON " .. i, "Orientation +15 degres")
    safe_call(ail, {"setHeadAngle", "setAngle", "setTargetAngle"}, 15)
    sleep(0.8)

    log("AILERON " .. i, "Orientation -15 degres")
    safe_call(ail, {"setHeadAngle", "setAngle", "setTargetAngle"}, -15)
    sleep(0.8)

    log("AILERON " .. i, "Remise a zero (0 degres)")
    safe_call(ail, {"setHeadAngle", "setAngle", "setTargetAngle"}, 0)
    sleep(0.5)
end

-------------------------------------------------------------------------------
-- 4. TEST TUYÈRE VECTORIELLE
-------------------------------------------------------------------------------
print("\n--- 4. TEST TUYÈRE VECTORIELLE ---")
local thruster = peripheral.find("creative_vector_thruster")

if thruster then
    log("TUYERE", "Allumage poussée (50%)...")
    safe_call(thruster, {"enable", "setActive"}, true)
    safe_call(thruster, {"setPowerNormalized", "setThrustNormalized", "setPower"}, 0.5)
    sleep(1)

    log("TUYERE", "Orienter vecteur (X=0.2, Y=1.0, Z=0.2)...")
    safe_call(thruster, {"setVector"}, 0.2, 1.0, 0.2)
    sleep(1.5)

    log("TUYERE", "Remise dans l'axe (X=0.0, Y=1.0, Z=0.0)...")
    safe_call(thruster, {"setVector"}, 0.0, 1.0, 0.0)
    sleep(1)

    log("TUYERE", "Coupure de la poussee...")
    safe_call(thruster, {"setPowerNormalized", "setThrustNormalized", "setPower"}, 0)
    safe_call(thruster, {"disable", "setActive"}, false)
else
    log("TUYERE", "Non detectee !")
end

print("\n========================================")
print("[SUCCÈS] Séquence de test terminée.")
print("========================================")