-- ============================================================================
-- SCRIPT DE VOL MISSILE : PID 3D & TOP-ATTACK (testvol.lua)
-- ============================================================================

-- 1. PARAMÈTRES DE VOL (À AJUSTER)
local HAUTEUR_SURVOL = 100  -- Hauteur (en blocs) de la phase de croisière
local RAYON_PLONGEE  = 20.0 -- Distance horizontale (en blocs) avant de piquer

-- 2. COORDONNÉES DE LA CIBLE
local tArgs = { ... }
local cibleX = tonumber(tArgs[1]) or 100
local cibleY = tonumber(tArgs[2]) or 70
local cibleZ = tonumber(tArgs[3]) or 100

print(string.format("Cible definie : X=%.1f, Y=%.1f, Z=%.1f", cibleX, cibleY, cibleZ))

-- 3. DÉTECTION DES PÉRIPHÉRIQUES
local gimbSensor = peripheral.find("gimbal") or peripheral.find("orientation_sensor") or peripheral.find("navigation")
local velSensor  = peripheral.find("velocity") or peripheral.find("motion_sensor")
local altSensor  = peripheral.find("altimeter") or peripheral.find("altitude")
local thruster   = peripheral.find("vector_thruster") or peripheral.find("thruster")

local function reglerVecteur(steerX, steerY)
    if thruster then
        if thruster.setVector then
            thruster.setVector(steerX, steerY)
        elseif thruster.setPitchYaw then
            thruster.setPitchYaw(steerY, steerX)
        elseif thruster.setRotation then
            thruster.setRotation(steerX, steerY)
        end
    end
end

local function reglerPoussee(valeur)
    if thruster then
        if thruster.setThrust then
            thruster.setThrust(valeur)
        elseif thruster.setThrottle then
            thruster.setThrottle(valeur)
        end
    end
end

-- 4. STRUCTURE PID 3D
local function creerPID(kp, ki, kd, minOut, maxOut)
    return {
        kp = kp, ki = ki, kd = kd,
        minOut = minOut or -1.0, maxOut = maxOut or 1.0,
        integral = 0, prevError = 0,
        update = function(self, err, dt)
            if not dt or dt <= 0 then dt = 0.05 end
            self.integral = math.max(-1.0, math.min(1.0, self.integral + err * dt))
            local derivative = (err - self.prevError) / dt
            self.prevError = err
            local output = (self.kp * err) + (self.ki * self.integral) + (self.kd * derivative)
            return math.max(self.minOut, math.min(self.maxOut, output))
        end
    }
end

-- Gains du contrôleur PID
local pidYaw   = creerPID(1.4, 0.02, 0.40, -1.0, 1.0)
local pidPitch = creerPID(1.4, 0.02, 0.40, -1.0, 1.0)

-- 5. INITIALISATION DU VOL
local PHASE = "LAUNCH"
local startY = nil

print("Initialisation du decollage vertical...")
local tempsPrecedent = os.clock()

while true do
    local tempsActuel = os.clock()
    local dt = tempsActuel - tempsPrecedent
    if dt <= 0 then dt = 0.05 end
    tempsPrecedent = tempsActuel

    -- A. Localisation GPS et Altitude
    local cx, cy, cz = gps.locate(0.05)
    if altSensor and altSensor.getHeight then
        local altExacte = altSensor.getHeight()
        if altExacte then cy = altExacte end
    end

    if cx then
        -- Enregistrement de l'altitude au point de lancement
        if not startY then startY = cy end

        -- B. Vitesse du missile
        local vx, vy, vz = 0, 0, 0
        if velSensor and velSensor.getVelocity then
            local v = velSensor.getVelocity()
            if type(v) == "table" then
                vx = v.x or v[1] or 0
                vy = v.y or v[2] or 0
                vz = v.z or v[3] or 0
            end
        end

        -- C. Lecture du cap et de l'assiette (Gimbal)
        local currentYawRad, currentPitchRad = 0, 0
        if gimbSensor then
            if gimbSensor.getAnglesRad then
                local a = gimbSensor.getAnglesRad()
                if type(a) == "table" then
                    currentPitchRad = a.pitch or a[1] or 0
                    currentYawRad   = a.yaw   or a[2] or 0
                end
            elseif gimbSensor.getAngles then
                local a = gimbSensor.getAngles()
                if type(a) == "table" then
                    currentPitchRad = math.rad(a.pitch or a[1] or 0)
                    currentYawRad   = math.rad(a.yaw   or a[2] or 0)
                end
            end
        end

        -- Variables cibles de la boucle
        local angleCibleYaw = 0
        local angleCiblePitch = 0
        local poussee = 1.0

        -- D. GESTION DES 3 PHASES DE VOL
        if PHASE == "LAUNCH" then
            -- Consigne : Pitch à +90° (vers le ciel), Yaw maintenu constant
            angleCiblePitch = math.pi / 2
            angleCibleYaw = currentYawRad
            poussee = 1.0

            if cy >= (startY + HAUTEUR_SURVOL) then
                PHASE = "CRUISE"
                print("Altitude atteinte. Transition vers CROISIERE.")
            end

        elseif PHASE == "CRUISE" then
            -- Cible virtuelle en hauteur
            local destX = cibleX
            local destY = cibleY + HAUTEUR_SURVOL
            local destZ = cibleZ

            local dx = destX - cx
            local dy = destY - cy
            local dz = destZ - cz

            -- Anticipation via vitesse
            local corrX = dx - (vx * 0.4)
            local corrY = dy - (vy * 0.4)
            local corrZ = dz - (vz * 0.4)

            angleCibleYaw = math.atan2(corrZ, corrX)
            local dist2D_dest = math.sqrt(corrX * corrX + corrZ * corrZ)
            angleCiblePitch = math.atan2(corrY, dist2D_dest)

            -- Modulation de poussée en croisière (ralentit un peu dans les virages serrés)
            local diffYaw = math.abs(angleCibleYaw - currentYawRad)
            poussee = math.max(0.5, math.cos(math.min(math.pi / 2, diffYaw)))

            -- Check distance d'engagement
            local dist2D_cible = math.sqrt((cibleX - cx)^2 + (cibleZ - cz)^2)
            if dist2D_cible < RAYON_PLONGEE then
                PHASE = "TERMINAL"
                print("Cible en vue ! Engagement TOP-ATTACK.")
            end

        elseif PHASE == "TERMINAL" then
            -- Cible au sol
            local dx = cibleX - cx
            local dy = cibleY - cy
            local dz = cibleZ - cz
            local distTotal = math.sqrt(dx * dx + dy * dy + dz * dz)

            -- Arrêt moteur si impact imminent
            if distTotal < 2.0 then
                print("IMPACT CIBLE !")
                reglerPoussee(0.0)
                reglerVecteur(0.0, 0.0)
                break
            end

            local corrX = dx - (vx * 0.3)
            local corrY = dy - (vy * 0.3)
            local corrZ = dz - (vz * 0.3)

            angleCibleYaw = math.atan2(corrZ, corrX)
            local dist2D = math.sqrt(corrX * corrX + corrZ * corrZ)
            angleCiblePitch = math.atan2(corrY, dist2D)

            poussee = 1.0 -- Plein gaz vers le sol !
        end

        -- E. CALCUL DES ERREURS (-PI à +PI) ET EXÉCUTION DU PID
        local errYaw = angleCibleYaw - currentYawRad
        while errYaw > math.pi do errYaw = errYaw - (2 * math.pi) end
        while errYaw < -math.pi do errYaw = errYaw + (2 * math.pi) end

        local errPitch = angleCiblePitch - currentPitchRad
        while errPitch > math.pi do errPitch = errPitch - (2 * math.pi) end
        while errPitch < -math.pi do errPitch = errPitch + (2 * math.pi) end

        local steerX = pidYaw:update(errYaw, dt)
        local steerY = pidPitch:update(errPitch, dt)

        -- F. APPLICATION AU PROPULSEUR
        reglerVecteur(steerX, steerY)
        reglerPoussee(poussee)
    else
        print("En attente de coordonnees GPS...")
    end

    sleep(0)
end