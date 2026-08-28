-- Configuration
local TARGET_ALTITUDE_GAIN = 200  -- Gain d'altitude visé (200 blocs au-dessus du point de départ)
local LOG_FILE = "flight_log.json" -- Fichier de télémétrie (écrasé à chaque lancement)

-- Détection et liaison des périphériques
local thruster = peripheral.wrap("creative_vector_thruster_15") or peripheral.find("creative_vector_thruster")
local alt_sensor = peripheral.wrap("altitude_sensor_9") or peripheral.find("altitude_sensor")
local vel_sensor = peripheral.wrap("velocity_sensor_10") or peripheral.find("velocity_sensor")
local gimbal_sensor = peripheral.wrap("gimbal_sensor_14") or peripheral.find("gimbal_sensor")
local aileron = peripheral.wrap("aileron_bearing_1") or peripheral.find("aileron_bearing")

if not thruster then
    error("Erreur: Périphérique 'creative_vector_thruster' introuvable !")
end
if not alt_sensor then
    error("Erreur: Périphérique 'altitude_sensor' introuvable !")
end

-- Fonction pour lire l'altitude selon l'API du capteur
local function get_current_altitude()
    if alt_sensor.getAltitude then
        return alt_sensor.getAltitude()
    elseif alt_sensor.getPosition then
        local _, y, _ = alt_sensor.getPosition()
        return y
    elseif alt_sensor.read then
        local data = alt_sensor.read()
        if type(data) == "table" and data.y then return data.y end
        if type(data) == "number" then return data end
    end
    return 0
end

-- Initialisation du vol
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

-- Structure de stockage pour la télémétrie
local flight_data = {
    launch_timestamp = os.epoch("utc"),
    start_altitude = start_altitude,
    target_altitude = target_altitude,
    records = {}
}

-- Fonction de capture instantanée (20Hz)
local function capture_telemetry(tick, start_time)
    local current_alt = get_current_altitude()
    
    -- Vitesse (V_x, V_y, V_z)
    local vx, vy, vz = 0, 0, 0
    if vel_sensor then
        if vel_sensor.getVelocity then
            vx, vy, vz = vel_sensor.getVelocity()
        elseif vel_sensor.read then
            local v = vel_sensor.read()
            if type(v) == "table" then
                vx, vy, vz = v.x or 0, v.y or 0, v.z or 0
            end
        end
    end

    -- Orientation (Pitch, Yaw, Roll)
    local pitch, yaw, roll = 0, 0, 0
    if gimbal_sensor then
        if gimbal_sensor.getOrientation then
            pitch, yaw, roll = gimbal_sensor.getOrientation()
        elseif gimbal_sensor.getPitch then
            pitch = gimbal_sensor.getPitch() or 0
            yaw = gimbal_sensor.getYaw() or 0
            roll = gimbal_sensor.getRoll() or 0
        elseif gimbal_sensor.read then
            local g = gimbal_sensor.read()
            if type(g) == "table" then
                pitch, yaw, roll = g.pitch or 0, g.yaw or 0, g.roll or 0
            end
        end
    end

    return {
        tick = tick,
        timestamp_ms = os.epoch("utc"),
        time_elapsed_s = (os.epoch("utc") - start_time) / 1000.0,
        altitude = current_alt,
        rel_altitude = current_alt - start_altitude,
        velocity = { x = vx, y = vy, z = vz },
        orientation = { pitch = pitch, yaw = yaw, roll = roll }
    }
end

-- Stabilisation de l'aileron droit au décollage
if aileron and aileron.setTargetAngle then
    aileron.setTargetAngle(0)
end

-- Poussée vectorielle vers le haut (Axe Y = 1)
if thruster.setVector then
    thruster.setVector(0, 1, 0)
elseif thruster.setTargetVector then
    thruster.setTargetVector(0, 1, 0)
end

if thruster.setPower then
    thruster.setPower(1.0)
elseif thruster.setThrust then
    thruster.setThrust(1.0)
elseif thruster.enable then
    thruster.enable()
end

print("[LAUNCH] Moteurs allumés. Décollage vertical...")

-- Boucle cadencée à 20Hz (1 tick Minecraft = 0.05 seconde)
local running = true
local tick = 0
local launch_start_time = os.epoch("utc")
local timer_id = os.startTimer(0.05)

while running do
    local event, id = os.pullEvent("timer")
    if id == timer_id then
        tick = tick + 1
        
        -- Capture télémétrique
        local snapshot = capture_telemetry(tick, launch_start_time)
        table.insert(flight_data.records, snapshot)

        -- Affichage écran en temps réel
        term.setCursorPos(1, 8)
        term.clearLine()
        write(string.format("Tick: %-5d | Alt: %6.1fm | Gain: %6.1f / %dm", 
            tick, snapshot.altitude, snapshot.rel_altitude, TARGET_ALTITUDE_GAIN))

        -- Condition d'arrêt (+200 blocs franchis)
        if snapshot.rel_altitude >= TARGET_ALTITUDE_GAIN then
            print("\n\n[CIBLE ATTEINTE] Coupure moteur à +" .. math.floor(snapshot.rel_altitude) .. "m !")
            running = false
        else
            -- Réarmement de l'horloge 20Hz
            timer_id = os.startTimer(0.05)
        end
    end
end

-- Coupure des propulseurs
if thruster.setPower then
    thruster.setPower(0)
elseif thruster.setThrust then
    thruster.setThrust(0)
elseif thruster.disable then
    thruster.disable()
end

-- Écriture et écrasement du fichier de télémétrie
print("[SAUVEGARDE] Enregistrement du vol dans " .. LOG_FILE .. "...")
local file = fs.open(LOG_FILE, "w")
if file then
    file.write(textutils.serializeJSON(flight_data))
    file.close()
    print("[SUCCÈS] Télémétrie enregistrée (" .. #flight_data.records .. " enregistrements à 20Hz).")
else
    print("[ERREUR] Impossible de sauvegarder le fichier de vol.")
end
