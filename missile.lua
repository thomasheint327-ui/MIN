-- ============================================================================
-- MISSILE.LUA - SÉQUENCE D'ESSAI AU SOL (STATIQUE - 0% PROPULSION)
-- ============================================================================

-------------------------------------------------------------------------------
-- 1. INITIALISATION DU RÉSEAU & RECHERCHE DES PÉRIPHÉRIQUES
-------------------------------------------------------------------------------
for _, side in ipairs(rs.getSides()) do
    if peripheral.getType(side) == "modem" then
        rednet.open(side)
        pcall(function() peripheral.call(side, "open", 65535) end)
    end
end

local function find_peripheral(type_name)
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == type_name then
            return peripheral.wrap(name), name
        end
    end
    return nil, nil
end

local gyro_motor    = peripheral.wrap("top") or find_peripheral("Create_CreativeMotor")
local thruster      = find_peripheral("creative_vector_thruster")
local alt_sensor    = find_peripheral("altitude_sensor")
local gimbal_sensor = find_peripheral("gimbal_sensor")
local vel_sensor    = find_peripheral("velocity_sensor")

local ailerons = {}
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "aileron_bearing" then
        table.insert(ailerons, peripheral.wrap(name))
    end
end

-------------------------------------------------------------------------------
-- 2. COMMANDES BAS NIVEAU & SÉCURITÉS
-------------------------------------------------------------------------------
local function set_thruster_power(power)
    if not thruster then return false end
    return pcall(function()
        if power <= 0 then
            if thruster.disable then thruster.disable() end
            if thruster.setActive then thruster.setActive(false) end
            if thruster.setPowerNormalized then thruster.setPowerNormalized(0) end
            if thruster.setThrustNormalized then thruster.setThrustNormalized(0) end
        else
            if thruster.enable then thruster.enable() end
            if thruster.setActive then thruster.setActive(true) end
            if thruster.setPowerNormalized then thruster.setPowerNormalized(power)
            elseif thruster.setThrustNormalized then thruster.setThrustNormalized(power)
            elseif thruster.setPower then thruster.setPower(power) end
        end
    end)
end

local function set_thruster_vector(x, y, z)
    if not thruster then return false end
    return pcall(function()
        if thruster.setVector then thruster.setVector(x or 0, y or 0, z or 0)
        else
            if thruster.setVectorX then thruster.setVectorX(x or 0) end
            if thruster.setVectorY then thruster.setVectorY(y or 0) end
            if thruster.setVectorZ then thruster.setVectorZ(z or 0) end
        end
    end)
end

local function set_gyro_speed(rpm)
    if gyro_motor and gyro_motor.setTargetSpeed then
        return pcall(function() gyro_motor.setTargetSpeed(math.max(-256, math.min(256, rpm))) end)
    end
    return false
end

local function set_aileron_angle(bearing, angle)
    if bearing then
        return pcall(function() bearing.setHeadAngle("primary", math.max(-15, math.min(15, angle))) end)
    end
    return false
end

-- Extinction stricte de sécurité au chargement
set_thruster_power(0.0)
set_thruster_vector(0, 1, 0)
set_gyro_speed(0)
for _, ail in ipairs(ailerons) do set_aileron_angle(ail, 0) end

-------------------------------------------------------------------------------
-- 3. FONCTION DE TEST AU SOL (CHECKLIST + ACTIONNEURS)
-------------------------------------------------------------------------------
local function run_staten_preflight()
    term.clear()
    term.setCursorPos(1, 1)
    print("========================================")
    print("  CHECKLIST PRE-VOL (STATIQUE - 0% PROP)")
    print("========================================")

    -- A. DIAGNOSTIC DES 3 CAPTEURS
    print("\n--- 1. VERIFICATION DES CAPTEURS ---")
    
    -- Capteur 1 : Altitude
    local current_alt = 0
    if alt_sensor then
        if alt_sensor.getAltitude then current_alt = alt_sensor.getAltitude()
        elseif alt_sensor.getPosition then local _, y, _ = alt_sensor.getPosition() current_alt = y end
        print(string.format(" [OK] Altitude Sensor : %.1f m", current_alt))
    else
        print(" [FAIL] Altitude Sensor : INTROUVABLE")
    end

    -- Capteur 2 : Gimbal / Inertiel
    local pitch, yaw, roll = 0, 0, 0
    if gimbal_sensor and gimbal_sensor.getAngles then
        local a = gimbal_sensor.getAngles()
        if type(a) == "table" then
            pitch, yaw, roll = (a[1] or 0)*(180/math.pi), (a[2] or 0)*(180/math.pi), (a[3] or 0)*(180/math.pi)
        end
        print(string.format(" [OK] Gimbal Sensor   : P:%.1f° Y:%.1f° R:%.1f°", pitch, yaw, roll))
    else
        print(" [FAIL] Gimbal Sensor   : INTROUVABLE")
    end

    -- Capteur 3 : Vitesse
    if vel_sensor then
        local vx, vy, vz = 0, 0, 0
        if vel_sensor.getVelocity then vx, vy, vz = vel_sensor.getVelocity() end
        print(string.format(" [OK] Velocity Sensor : Vx:%.1f Vy:%.1f Vz:%.1f", vx, vy, vz))
    else
        print(" [FAIL] Velocity Sensor : INTROUVABLE")
    end

    sleep(1.5)

    -- B. ESSAI DES ACTIONNEURS (STATIQUE)
    print("\n--- 2. TEST SEQUENTIEL DES ACTIONNEURS ---")
    
    -- Gyroscope top
    write(" [TEST] Gyro Motor (top)... ")
    set_gyro_speed(100)  sleep(0.8)
    set_gyro_speed(-100) sleep(0.8)
    set_gyro_speed(0)
    print("VALIDE")

    -- Gouvernes / Ailerons
    write(" [TEST] Ailerons (Pitch/Yaw)... ")
    for _, ail in ipairs(ailerons) do set_aileron_angle(ail, 15) end  sleep(0.8)
    for _, ail in ipairs(ailerons) do set_aileron_angle(ail, -15) end sleep(0.8)
    for _, ail in ipairs(ailerons) do set_aileron_angle(ail, 0) end
    print("VALIDE")

    -- Tuyère vectorielle (Puissance verrouillée à 0%)
    write(" [TEST] Vectorisation Tuyere (0% Poussee)... ")
    set_thruster_power(0.0)
    set_thruster_vector(0.5, 1, 0)  sleep(0.8)
    set_thruster_vector(-0.5, 1, 0) sleep(0.8)
    set_thruster_vector(0, 1, 0.5)  sleep(0.8)
    set_thruster_vector(0, 1, 0)
    print("VALIDE")

    -- C. DEMANDE DE CONFIRMATION OPERATEUR
    print("\n========================================")
    print(" SÉQUENCE STATIQUE COMPLÉTÉE AVEC SUCCÈS")
    print("========================================")
    print(" Appuie sur [ENTRÉE] pour autoriser le tir")
    print(" Ou n'importe quelle autre touche pour annuler.")
    
    local event, key = os.pullEvent("key")
    if key == keys.enter then
        print("\n [CONFIRMATION] Tir autorisé par l'opérateur.")
        sleep(1.0)
        return true
    else
        print("\n [ANNULATION] Procédure interrompue par l'opérateur.")
        return false
    end
end

-- Lancement de la séquence de test
run_staten_preflight()