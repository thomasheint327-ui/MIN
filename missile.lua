-- Configuration
local TARGET_ALTITUDE_GAIN = 200  -- Altitude visée (+200 blocs)
local LOG_FILE = "flight_log.json"

-- GAINS PID OPTIMISÉS (Ultra-réactifs pour corriger immédiatement au sol)
local KP = 3.5        -- Correction forte dès le moindre degré de dérive
local KD = 0.8        -- Amortissement pour éviter le pompage au retour au centre
local DEADBAND = 0.1  -- Réponse immédiate (déclenché dès 0.1° de pente)

-- INVERSION DES AXES (Change à true/false selon le comportement au tir)
local INVERT_PITCH = true
local INVERT_YAW   = true

-- Détection automatique par TYPE (évite les bugs d'IDs modifiés)
local function find_peripheral(type_name)
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == type_name then
            return peripheral.wrap(name), name
        end
    end
    return nil, nil
end

local thruster, thruster_name    = find_peripheral("creative_vector_thruster")
local alt_sensor, alt_name       = find_peripheral("altitude_sensor")
local gimbal_sensor, gimbal_name = find_peripheral("gimbal_sensor")

-- Récupération dynamique des 2 ailerons
local ailerons = {}
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "aileron_bearing" then
        table.insert(ailerons, peripheral.wrap(name))
    end
end

local aileron_pitch = ailerons[1]
local aileron_yaw   = ailerons[2]

if not thruster or not alt_sensor then
    error("Erreur: Propulseur ou Altimètre introuvable !")
end

if not aileron_pitch or not aileron_yaw then
    error("Erreur: Les 2 ailerons ne sont pas tous les deux détectés !")
end

-- Re-wrap automatique en vol (sécurité VS2)
local function update_peripherals()
    if not aileron_pitch and ailerons[1] then aileron_pitch = ailerons[1] end
    if not aileron_yaw and ailerons[2] then aileron_yaw = ailerons[2] end
    if not gimbal_sensor then gimbal_sensor = find_peripheral("gimbal_sensor") end
end

local function get_current_altitude()
    if alt_sensor.getAltitude then return alt_sensor.getAltitude() end
    if alt_sensor.getPosition then local _, y, _ = alt_sensor.getPosition() return y end
    return 0
end

local function set_thruster_power(power)
    if thruster then
        if thruster.setPowerNormalized then
            thruster.setPowerNormalized(power)
        elseif thruster.setThrustNormalized then
            thruster.setThrustNormalized(power)
        elseif thruster.setPower then
            thruster.setPower(power)
        elseif thruster.enable then
            if power > 0 then thruster.enable() else thruster.disable() end
        end
    end
end

local function set_thruster_vector(x, y, z)
    if not thruster then return end
    if thruster.setVector then
        thruster.setVector(x or 0, y or 0, z or 0)
    else
        if thruster.setVectorX then thruster.setVectorX(x or 0) end
        if thruster.setVectorY then thruster.setVectorY(y or 0) end
        if thruster.setVectorZ then thruster.setVectorZ(z or 0) end
    end
end

local function push_missile()
    set_thruster_vector(0, 1, 0)
    set_thruster_power(1.0)
end

-- Lecture d'orientation (Conversion Radians -> Degrés)
local function get_orientation_degrees()
    update_peripherals()
    if gimbal_sensor and gimbal_sensor.getAngles then
        local angles = gimbal_sensor.getAngles()
        if type(angles) == "table" then
            local pitch_rad = angles[1] or 0
            local yaw_rad   = angles[2] or 0
            local roll_rad  = angles[3] or 0

            return pitch_rad * (180 / math.pi), yaw_rad * (180 / math.pi), roll_rad * (180 / math.pi)
        end
    end
    return 0, 0, 0
end

-- Commande de l'aileron (plage -45° à +45°)
local function set_aileron_angle(bearing, angle)
    if bearing then
        local clamped_angle = math.max(-45, math.min(45, angle))
        pcall(function()
            bearing.setHeadAngle("primary", clamped_angle)
        end)
    end
end

local start_altitude = get_current_altitude()

-- Remise au neutre au départ
set_aileron_angle(aileron_pitch, 0)
set_aileron_angle(aileron_yaw, 0)

-- Allumage de la poussée vers le haut
push_missile()

local flight_data = {
    launch_timestamp = os.epoch("utc"),
    start_altitude = start_altitude,
    records = {}
}

local last_pitch_err = 0
local last_yaw_err = 0
local running = true
local tick = 0
local launch_start_time = os.epoch("utc")
local timer_id = os.startTimer(0.05)

term.clear()
term.setCursorPos(1, 1)
print("========================================")
print("     GUIDAGE MISSILE (PITCH & YAW)     ")
print("========================================")
print(string.format("Altitude de départ : %.2f m", start_altitude))
print("[LAUNCH] Décollage en cours...")

while running do
    local event, id = os.pullEvent("timer")
    if id == timer_id then
        tick = tick + 1
        update_peripherals()

        local cur_time = os.epoch("utc")
        local cur_alt = get_current_altitude()
        local rel_alt = cur_alt - start_altitude

        -- Angles en Degrés
        local pitch, yaw, roll = get_orientation_degrees()

        -- Erreurs d'inclinaison avec prise en compte des inversions
        local pitch_err = INVERT_PITCH and pitch or -pitch
        local yaw_err   = INVERT_YAW and yaw or -yaw

        -- Zone morte fine (0.1°)
        if math.abs(pitch_err) < DEADBAND then pitch_err = 0 end
        if math.abs(yaw_err) < DEADBAND then yaw_err = 0 end

        local pitch_rate = pitch_err - last_pitch_err
        local yaw_rate   = yaw_err - last_yaw_err

        last_pitch_err = pitch_err
        last_yaw_err = yaw_err

        -- Calcul des ordres d'angles
        local cmd_pitch = (pitch_err * KP) + (pitch_rate * KD)
        local cmd_yaw   = (yaw_err * KP)   + (yaw_rate * KD)

        -- Envoi aux ailerons
        set_aileron_angle(aileron_pitch, cmd_pitch)
        set_aileron_angle(aileron_yaw, cmd_yaw)

        -- Enregistrement de la télémétrie
        table.insert(flight_data.records, {
            tick = tick,
            time_s = (cur_time - launch_start_time) / 1000.0,
            altitude = cur_alt,
            rel_altitude = rel_alt,
            orientation = { pitch = pitch, yaw = yaw, roll = roll },
            commands = { pitch = cmd_pitch, yaw = cmd_yaw }
        })

        -- Affichage console en direct
        term.setCursorPos(1, 7)
        term.clearLine()
        write(string.format("Alt: %6.1fm | Pitch: %5.1f° -> %5.1f°", rel_alt, pitch, cmd_pitch))
        term.setCursorPos(1, 8)
        term.clearLine()
        write(string.format("            | Yaw  : %5.1f° -> %5.1f°", yaw, cmd_yaw))

        if rel_alt >= TARGET_ALTITUDE_GAIN then
            running = false
        else
            timer_id = os.startTimer(0.05)
        end
    end
end

-- Coupure moteur et remise au neutre
set_thruster_power(0)
set_aileron_angle(aileron_pitch, 0)
set_aileron_angle(aileron_yaw, 0)

-- Écriture du fichier log
local file = fs.open(LOG_FILE, "w")
if file then
    file.write(textutils.serializeJSON(flight_data))
    file.close()
    print("\n\n[CIBLE ATTEINTE] Vol terminé et log sauvegardé !")
end
