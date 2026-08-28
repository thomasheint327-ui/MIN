-- Configuration
local TARGET_ALTITUDE_GAIN = 200  -- Altitude visée (+200 blocs)
local LOG_FILE = "flight_log.json"

-- Gains PID (Réglés pour la plage -45° à +45°)
local KP = 1.8         -- Force de correction
local KD = 0.4         -- Amortissement
local DEADBAND = 0.8   -- Zone morte en degrés (ignore les dérives < 0.8°)

-- Noms des périphériques
local thruster_name = "creative_vector_thruster_16"
local alt_name      = "altitude_sensor_10"
local gimbal_name   = "gimbal_sensor_15"
local pitch_name    = "aileron_bearing_6"
local yaw_name      = "aileron_bearing_7"

local thruster      = peripheral.wrap(thruster_name)
local alt_sensor    = peripheral.wrap(alt_name)
local gimbal_sensor = peripheral.wrap(gimbal_name)
local aileron_pitch = peripheral.wrap(pitch_name)
local aileron_yaw   = peripheral.wrap(yaw_name)

if not thruster or not alt_sensor then
    error("Erreur: Propulseur ou Altimètre introuvable !")
end

-- Re-wrap automatique en vol (sécurité VS2)
local function update_peripherals()
    if not aileron_pitch then aileron_pitch = peripheral.wrap(pitch_name) end
    if not aileron_yaw then aileron_yaw = peripheral.wrap(yaw_name) end
    if not gimbal_sensor then gimbal_sensor = peripheral.wrap(gimbal_name) end
end

local function get_current_altitude()
    if alt_sensor.getAltitude then return alt_sensor.getAltitude() end
    if alt_sensor.getPosition then local _, y, _ = alt_sensor.getPosition() return y end
    return 0
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
        -- Sécurité de bornage strict à ±45°
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
if thruster.setVector then thruster.setVector(0, 1, 0) end
if thruster.setPower then thruster.setPower(1.0) elseif thruster.enable then thruster.enable() end

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

        -- Erreurs par rapport au vol vertical (0°)
        local pitch_err = -pitch
        local yaw_err   = -yaw

        -- Application de la zone morte (évite de faire trembler les ailerons)
        if math.abs(pitch_err) < DEADBAND then pitch_err = 0 end
        if math.abs(yaw_err) < DEADBAND then yaw_err = 0 end

        local pitch_rate = pitch_err - last_pitch_err
        local yaw_rate   = yaw_err - last_yaw_err

        last_pitch_err = pitch_err
        last_yaw_err = yaw_err

        -- Calcul des ordres d'angles
        local cmd_pitch = (pitch_err * KP) + (pitch_rate * KD)
        local cmd_yaw = (yaw_err * KP) + (yaw_rate * KD)

        -- Application directe aux ailerons 6 et 7
        set_aileron_angle(aileron_pitch, cmd_pitch)
        set_aileron_angle(aileron_yaw, cmd_yaw)

        -- Sauvegarde télémétrique
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
if thruster.setPower then thruster.setPower(0) end
set_aileron_angle(aileron_pitch, 0)
set_aileron_angle(aileron_yaw, 0)

-- Écriture du fichier log
local file = fs.open(LOG_FILE, "w")
if file then
    file.write(textutils.serializeJSON(flight_data))
    file.close()
    print("\n\n[CIBLE ATTEINTE] Vol terminé et log sauvegardé !")
end
