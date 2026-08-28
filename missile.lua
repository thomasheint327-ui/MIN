-- Configuration
local TARGET_ALTITUDE_GAIN = 200  -- Altitude visée (+200 blocs au-dessus du départ)
local LOG_FILE = "flight_log.json" -- Fichier de sauvegarde de la télémétrie

-- Détection des périphériques
local thruster = peripheral.wrap("creative_vector_thruster_15") or peripheral.find("creative_vector_thruster")
local alt_sensor = peripheral.wrap("altitude_sensor_9") or peripheral.find("altitude_sensor")
local vel_sensor = peripheral.wrap("velocity_sensor_10") or peripheral.find("velocity_sensor")
local gimbal_sensor = peripheral.wrap("gimbal_sensor_14") or peripheral.find("gimbal_sensor")
local aileron = peripheral.wrap("aileron_bearing_1") or peripheral.find("aileron_bearing")

if not thruster then error("Erreur: Propulseur 'creative_vector_thruster' introuvable !") end
if not alt_sensor then error("Erreur: Altimètre 'altitude_sensor' introuvable !") end

-- Fonction pour lire l'altitude
local function get_current_altitude()
    if alt_sensor.getAltitude then
        return alt_sensor.getAltitude()
    elseif alt_sensor.getPosition then
        local _, y, _ = alt_sensor.getPosition()
        return y
    end
    return 0
end

-- Initialisation de l'altitude
local start_altitude = get_current_altitude()
local target_altitude = start_altitude + TARGET_ALTITUDE_GAIN

term.clear()
term.setCursorPos(1, 1)
print("========================================")
print("      SYSTEME DE LANCEMENT MISSILE      ")
print("========================================")
print(string.format("Altitude de départ : %.2f m", start_altitude))
print(string.format("Altitude cible     : %.2f m (+%d m)", target_altitude, TARGET_ALTITUDE_GAIN))
print("----------------------------------------")

-- Verrouillage des ailerons au neutre (0°) pour un tir parfaitement droit
if aileron then
    if aileron.setHeadAngle then
        aileron.setHeadAngle("primary", 0)
        aileron.setHeadAngle("secondary", 0)
    elseif aileron.clearAngles then
        aileron.clearAngles()
    end
end

-- Allumage de la poussée vectorielle vers le haut (Y = 1)
if thruster.setVector then
    thruster.setVector(0, 1, 0)
elseif thruster.setTargetVector then
    thruster.setTargetVector(0, 1, 0)
end

if thruster.setPower then
    thruster.setPower(1.0)
elseif thruster.enable then
    thruster.enable()
end

print("[LAUNCH] Allumage des moteurs - DÉCOLLAGE...")

-- Données de télémétrie
local flight_data = {
    launch_timestamp = os.epoch("utc"),
    start_altitude = start_altitude,
    target_altitude = target_altitude,
    records = {}
}

-- Capture télémétrique à 20Hz
local function capture_telemetry(tick, start_time)
    local cur_alt = get_current_altitude()
    
    local vx, vy, vz = 0, 0, 0
    if vel_sensor and vel_sensor.getVelocity then
        vx, vy, vz = vel_sensor.getVelocity()
    end

    local pitch, yaw, roll = 0, 0, 0
    if gimbal_sensor and gimbal_sensor.getOrientation then
        pitch, yaw, roll = gimbal_sensor.getOrientation()
    end

    return {
        tick = tick,
        timestamp_ms = os.epoch("utc"),
        time_elapsed_s = (os.epoch("utc") - start_time) / 1000.0,
        altitude = cur_alt,
        rel_altitude = cur_alt - start_altitude,
        velocity = { x = vx, y = vy, z = vz },
        orientation = { pitch = pitch, yaw = yaw, roll = roll }
    }
end

-- Boucle de vol (1 tick = 0.05 s = 20 Hz)
local running = true
local tick = 0
local launch_start_time = os.epoch("utc")
local timer_id = os.startTimer(0.05)

while running do
    local event, id = os.pullEvent("timer")
    if id == timer_id then
        tick = tick + 1
        
        local snapshot = capture_telemetry(tick, launch_start_time)
        table.insert(flight_data.records, snapshot)

        -- Affichage écran en temps réel
        term.setCursorPos(1, 8)
        term.clearLine()
        write(string.format("Tick: %-5d | Alt: %6.1fm | Gain: %6.1f / %dm", 
            tick, snapshot.altitude, snapshot.rel_altitude, TARGET_ALTITUDE_GAIN))

        -- Coupure au franchissement des +200m
        if snapshot.rel_altitude >= TARGET_ALTITUDE_GAIN then
            print("\n\n[CIBLE ATTEINTE] Coupure des moteurs à +" .. math.floor(snapshot.rel_altitude) .. "m !")
            running = false
        else
            timer_id = os.startTimer(0.05)
        end
    end
end

-- Extinction des moteurs
if thruster.setPower then
    thruster.setPower(0)
elseif thruster.disable then
    thruster.disable()
end

-- Enregistrement du fichier JSON
print("[SAUVEGARDE] Écriture des données dans " .. LOG_FILE .. "...")
local file = fs.open(LOG_FILE, "w")
if file then
    file.write(textutils.serializeJSON(flight_data))
    file.close()
    print("[SUCCÈS] Télémétrie enregistrée (" .. #flight_data.records .. " mesures).")
else
    print("[ERREUR] Impossible de sauvegarder la télémétrie.")
end
