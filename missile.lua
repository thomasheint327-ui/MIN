-- ============================================================================
-- MISSILE.LUA - TEST PRE-VOL STATIQUE & MONTEE VERTICALE (PHASE 1)
-- ============================================================================

-------------------------------------------------------------------------------
-- 1. CONFIGURATION ET CONSTANTES
-------------------------------------------------------------------------------
local TARGET_ALTITUDE_GAIN = 200 -- Gain d'altitude visé (+200 blocs)

-- Gains PID Ailerons (±15° max)
local KP_AILERONS = 0.8
local KD_AILERONS = 0.3

-- Gains PID Gyroscope (Creative Motor sur 'top')
local KP_GYRO = 12.0
local KD_GYRO = 1.5
local MAX_RPM = 256
local DEADBAND = 0.2

-------------------------------------------------------------------------------
-- 2. INITIALISATION ET RECHERCHE PÉRIPHÉRIQUES
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
-- 3. COMMANDES ET LECTURES SÉCURISÉES
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
        return pcall(function() gyro_motor.setTargetSpeed(math.max(-MAX_RPM, math.min(MAX_RPM, rpm))) end)
    end
    return false
end

local function set_aileron_angle(bearing, angle)
    if bearing then
        return pcall(function() bearing.setHeadAngle("primary", math.max(-15, math.min(15, angle))) end)
    end
    return false
end

-- Formatage sécurisé des lectures capteurs
local function get_safe_altitude()
    if alt_sensor then
        if alt_sensor.getAltitude then return alt_sensor.getAltitude() end
        if alt_sensor.getPosition then local _, y, _ = alt_sensor.getPosition() return y end
    end
    return 0
end

local function get_safe_orientation()
    if gimbal_sensor and gimbal_sensor.getAngles then
        local a = gimbal_sensor.getAngles()
        if type(a) == "table" then
            return (a[1] or 0) * (180 / math.pi), (a[2] or 0) * (180 / math.pi), (a[3] or 0) * (180 / math.pi)
        end
    end
    return 0, 0, 0
end

local function get_safe_velocity()
    if vel_sensor and vel_sensor.getVelocity then
        local v1, v2, v3 = vel_sensor.getVelocity()
        if type(v1) == "table" then
            return v1.x or v1[1] or 0, v1.y or v1[2] or 0, v1.z or v1[3] or 0
        else
            return v1 or 0, v2 or 0, v3 or 0
        end
    end
    return 0, 0, 0
end

-- VERROUILLAGE SÉCURITÉ IMMÉDIAT AU CHARGEMENT
set_thruster_power(0.0)
set_thruster_vector(0, 1, 0)
set_gyro_speed(0)
for _, ail in ipairs(ailerons) do set_aileron_angle(ail, 0) end

-------------------------------------------------------------------------------
-- 4. ÉTAPE 1 : ESSAI STATIQUE AU SOL ET VALIDATION MANUELLE
-------------------------------------------------------------------------------
local function run_staten_preflight()
    term.clear()
    term.setCursorPos(1, 1)
    print("========================================")
    print("  CHECKLIST PRE-VOL (STATIQUE - 0% PROP)")
    print("========================================")

    -- A. DIAGNOSTIC DES CAPTEURS
    print("\n--- 1. VERIFICATION DES CAPTEURS ---")
    
    -- Altitude Sensor
    local current_alt = get_safe_altitude()
    if alt_sensor then
        print(string.format(" [OK] Altitude Sensor : %.1f m", current_alt))
    else
        print(" [FAIL] Altitude Sensor : INTROUVABLE")
    end

    -- Gimbal Sensor
    local pitch, yaw, roll = get_safe_orientation()
    if gimbal_sensor then
        print(string.format(" [OK] Gimbal Sensor   : P:%.1f° Y:%.1f° R:%.1f°", pitch, yaw, roll))
    else
        print(" [FAIL] Gimbal Sensor   : INTROUVABLE")
    end

    -- Velocity Sensor
    local vx, vy, vz = get_safe_velocity()
    if vel_sensor then
        print(string.format(" [OK] Velocity Sensor : Vx:%.1f Vy:%.1f Vz:%.1f", vx, vy, vz))
    else
        print(" [FAIL] Velocity Sensor : INTROUVABLE")
    end

    sleep(1.5)

    -- B. ESSAI DES ACTIONNEURS (STATIQUE 0%)
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

    -- Tuyère vectorielle (0% Poussée)
    write(" [TEST] Vectorisation Tuyere (0% Poussee)... ")
    set_thruster_power(0.0)
    set_thruster_vector(0.5, 1, 0)  sleep(0.8)
    set_thruster_vector(-0.5, 1, 0) sleep(0.8)
    set_thruster_vector(0, 1, 0.5)  sleep(0.8)
    set_thruster_vector(0, 1, 0)
    print("VALIDE")

    -- C. CONFIRMATION DE L'OPÉRATEUR
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

-------------------------------------------------------------------------------
-- 5. ÉTAPE 2 : VOL VERTICAL (PHASE 1)
-------------------------------------------------------------------------------
local function run_phase_1()
    local start_alt  = get_safe_altitude()
    local target_alt = start_alt + TARGET_ALTITUDE_GAIN

    term.clear()
    term.setCursorPos(1, 1)
    print("========================================")
    print("     MISSILE : DÉCOLLAGE ET PHASE 1")
    print("========================================")
    print(string.format("Altitude de départ  : %.1f m", start_alt))
    print(string.format("Altitude de coupure : %.1f m", target_alt))

    -- Allumage de la poussée
    set_thruster_vector(0, 1, 0)
    set_thruster_power(1.0)

    local last_pitch_err = 0
    local running        = true
    local timer_id       = os.startTimer(0.05)

    while running do
        local event, id = os.pullEvent("timer")
        if id == timer_id then
            local cur_alt = get_safe_altitude()
            local rel_alt = cur_alt - start_alt

            local pitch = get_safe_orientation()

            local pitch_err = -pitch
            if math.abs(pitch_err) < DEADBAND then pitch_err = 0 end

            local pitch_rate = pitch_err - last_pitch_err
            last_pitch_err   = pitch_err

            -- Asservissements PID
            local cmd_pitch = (pitch_err * KP_AILERONS) + (pitch_rate * KD_AILERONS)
            if ailerons[1] then set_aileron_angle(ailerons[1], cmd_pitch) end
            if ailerons[2] then set_aileron_angle(ailerons[2], cmd_pitch) end

            local gyro_rpm = (pitch_err * KP_GYRO) + (pitch_rate * KD_GYRO)
            set_gyro_speed(gyro_rpm)

            local vector_x = math.max(-0.3, math.min(0.3, cmd_pitch / 15))
            set_thruster_vector(vector_x, 1.0, 0)

            -- Télémesure console
            term.setCursorPos(1, 7)
            term.clearLine()
            write(string.format("Alt: %6.1fm / %dm | Pitch: %5.1f°", rel_alt, TARGET_ALTITUDE_GAIN, pitch))
            term.setCursorPos(1, 8)
            term.clearLine()
            write(string.format("Ailerons: %5.1f° | Gyro: %5.0f RPM", cmd_pitch, gyro_rpm))

            if rel_alt >= TARGET_ALTITUDE_GAIN then
                running = false
            else
                timer_id = os.startTimer(0.05)
            end
        end
    end

    -- Coupure de sécurité à +200m
    set_thruster_power(0.0)
    set_thruster_vector(0, 1, 0)
    set_gyro_speed(0)
    for _, ail in ipairs(ailerons) do set_aileron_angle(ail, 0) end

    term.setCursorPos(1, 10)
    print("\n[FIN PHASE 1] Moteur coupé à +200m.")
end

-------------------------------------------------------------------------------
-- DÉCLENCHEMENT DU PROGRAMME
-------------------------------------------------------------------------------
if run_staten_preflight() then
    run_phase_1()
end