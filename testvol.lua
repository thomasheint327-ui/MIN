-- ============================================================================
-- SCRIPT DE VOL ET GUIDAGE PID VECTORIEL 3D (testvol.lua)
-- ============================================================================

-- 1. PARAMÈTRES DE VOL CONFIGURABLES
local HAUTEUR_SURVOL = 100  -- Hauteur (en blocs) de la phase de croisière
local RAYON_PLONGEE  = 20.0 -- Distance horizontale (en blocs) avant de piquer

-- 2. COORDONNÉES DE LA CIBLE (CLI OU REDNET)
-- Ex: "testvol 200 80 -150" ou via signal radio Rednet si aucun argument
local tArgs = { ... }
local cibleX, cibleY, cibleZ

if #tArgs >= 3 then
    cibleX = tonumber(tArgs[1])
    cibleY = tonumber(tArgs[2])
    cibleZ = tonumber(tArgs[3])
else
    -- Si aucun argument n'est donné, on vérifie s'il y a un message Rednet en attente
    local modem = peripheral.find("modem")
    if modem then
        rednet.open(peripheral.getName(modem))
        print("En attente des donnees de la telecommande (Rednet)...")
        local senderId, message = rednet.receive("CIBLE_MISSILE", 2) -- Timeout 2s
        if type(message) == "table" then
            cibleX = message.x
            cibleY = message.y
            cibleZ = message.z
        end
    end
    -- Valeurs par défaut si aucun argument ni message Rednet
    cibleX = cibleX or 100
    cibleY = cibleY or 70
    cibleZ = cibleZ or 100
end

print(string.format("Cible definie : X=%.1f, Y=%.1f, Z=%.1f", cibleX, cibleY, cibleZ))

-- 3. DÉTECTION DES PÉRIPHÉRIQUES
local gimbSensor = peripheral.find("gimbal") or peripheral.find("orientation_sensor") or peripheral.find("navigation")
local velSensor  = peripheral.find("velocity") or peripheral.find("motion_sensor")
local altSensor  = peripheral.find("altimeter") or peripheral.find("altitude")
local thruster   = peripheral.find("vector_thruster") or peripheral.find("thruster")

-- Fonctions d'adaptation des commandes au Vector Thruster
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

-- 4. STRUCTURE DU CONTRÔLEUR PID
local function creerPID(kp, ki, kd, minOut, maxOut)
    return {
        kp = kp, ki = ki, kd = kd,
        minOut = minOut or -1.0, maxOut = maxOut or 1.0,
        integral = 0, prevError = 0,
        update = function(self, err, dt)
            if not dt or dt <= 0 then dt = 0.05 end

            -- Anti-windup sur l'integrale (clamping entre -1 et 1)
            self.integral = math.max(-1.0, math.min(1.0, self.integral + err * dt))

            -- Calcul de la derivee (amortissement des oscillations)
            local derivative = (err - self.prevError) / dt
            self.prevError = err

            -- Sortie combinee P + I + D
            local output = (self.kp * err) + (self.ki * self.integral) + (self.kd * derivative)
            return math.max(self.minOut, math.min(self.maxOut, output))
        end,
        reset = function(self)
            self.integral = 0
            self.prevError = 0
        end
    }
end

-- Initialisation des REGULATEURS PID (Yaw & Pitch)
-- Gains : Kp = 1.2 (Force), Ki = 0.02 (Correction continue), Kd = 0.35 (Amortisseur)
local pidYaw   = creerPID(1.2, 0.02, 0.35, -1.0, 1.0)
local pidPitch = creerPID(1.2, 0.02, 0.35, -1.0, 1.0)

-- 5. INITIALISATION DE LA MACHINE À ÉTATS DE VOL
local PHASE = "LAUNCH"
local startY = nil

print("Demarrage du pilotage PID vectoriel (Phase LAUNCH)...")
local tempsPrecedent = os.clock()

while true do
    local tempsActuel = os.clock()
    local dt = tempsActuel - tempsPrecedent
    if dt <= 0 then dt = 0.05 end
    tempsPrecedent = tempsActuel

    -- A. Geolocalisation GPS et Altitude
    local cx, cy, cz = gps.locate(0.05)
    if altSensor and altSensor.getHeight then
        local altExacte = altSensor.getHeight()
        if altExacte then cy = altExacte end
    end

    if cx then
        -- Enregistrement de l'altitude au point de lancement
        if not startY then startY = cy end

        -- B. Vitesse actuelle du missile (Velocity Sensor)
        local vx, vy, vz = 0, 0, 0
        if velSensor and velSensor.getVelocity then
            local v = velSensor.getVelocity()
            if type(v) == "table" then
                vx = v.x or v[1] or 0
                vy = v.y or v[2] or 0
                vz = v.z or v[3] or 0
            end
        end

        -- C. Lecture des angles actuels du missile (Gimbal)
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

        local angleCibleYaw = 0
        local angleCiblePitch = 0
        local poussee = 1.0

        -- D. GESTION DES 3 PHASES DE VOL
        if PHASE == "LAUNCH" then
            -- Maintien de l'assiette verticale (+90 degres)
            angleCiblePitch = math.pi / 2
            angleCibleYaw = currentYawRad
            poussee = 1.0

            -- Passage en croisiere une fois l'altitude atteinte
            if cy >= (startY + HAUTEUR_SURVOL) then
                PHASE = "CRUISE"
                print(string.format("Altitude (+%dm) atteinte -> Phase CRUISE", HAUTEUR_SURVOL))
            end

        elseif PHASE == "CRUISE" then
            -- Cible virtuelle en altitude (au-dessus de la cible reelle)
            local destX = cibleX
            local destY = cibleY + HAUTEUR_SURVOL
            local destZ = cibleZ

            local dx = destX - cx
            local dy = destY - cy
            local dz = destZ - cz

            -- Correction par navigation proportionnelle (Anticipation)
            local corrX = dx - (vx * 0.4)
            local corrY = dy - (vy * 0.4)
            local corrZ = dz - (vz * 0.4)

            angleCibleYaw = math.atan2(corrZ, corrX)
            local dist2D_dest = math.sqrt(corrX * corrX + corrZ * corrZ)
            angleCiblePitch = math.atan2(corrY, dist2D_dest)

            -- Modulation dynamique de la poussee
            local errYawTemp = angleCibleYaw - currentYawRad
            while errYawTemp > math.pi do errYawTemp = errYawTemp - (2 * math.pi) end
            while errYawTemp < -math.pi do errYawTemp = errYawTemp + (2 * math.pi) end
            poussee = math.max(0.4, math.cos(math.min(math.pi / 2, math.abs(errYawTemp))))

            -- Verification de la distance horizontale par rapport a la cible finale
            local dist2D_cible = math.sqrt((cibleX - cx)^2 + (cibleZ - cz)^2)
            if dist2D_cible < RAYON_PLONGEE then
                PHASE = "TERMINAL"
                print("Proximite cible atteinte -> Phase TERMINAL (Top-Attack)")
            end

        elseif PHASE == "TERMINAL" then
            -- Pique direct vers la cible finale au sol
            local dx = cibleX - cx
            local dy = cibleY - cy
            local dz = cibleZ - cz
            local distTotal = math.sqrt(dx * dx + dy * dy + dz * dz)

            -- Condition d'arret / Impact
            if distTotal < 1.5 then
                print("Impact cible !")
                reglerPoussee(0.0)
                reglerVecteur(0.0, 0.0)
                break
            end

            local corrX = dx - (vx * 0.4)
            local corrY = dy - (vy * 0.4)
            local corrZ = dz - (vz * 0.4)

            angleCibleYaw = math.atan2(corrZ, corrX)
            local dist2D = math.sqrt(corrX * corrX + corrZ * corrZ)
            angleCiblePitch = math.atan2(corrY, dist2D)

            -- Plein gaz pour la phase d'impact
            poussee = 1.0
        end

        -- E. Calcul des erreurs d'angle normalisees (-PI a +PI)
        local errYaw = angleCibleYaw - currentYawRad
        while errYaw > math.pi do errYaw = errYaw - (2 * math.pi) end
        while errYaw < -math.pi do errYaw = errYaw + (2 * math.pi) end

        local errPitch = angleCiblePitch - currentPitchRad
        while errPitch > math.pi do errPitch = errPitch - (2 * math.pi) end
        while errPitch < -math.pi do errPitch = errPitch + (2 * math.pi) end

        -- F. Execution des PID
        local steerX = pidYaw:update(errYaw, dt)      -- Tuyere axe X (Lacet / Yaw)
        local steerY = pidPitch:update(errPitch, dt)  -- Tuyere axe Y (Tangage / Pitch)

        -- Application au Vector Thruster
        reglerVecteur(steerX, steerY)
        reglerPoussee(poussee)
    else
        print("Attente du signal GPS...")
    end

    sleep(0)
end