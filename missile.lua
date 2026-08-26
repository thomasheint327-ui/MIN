-- ===================================================================
-- MISSILE.LUA - SYSTEME COMPLET (Guidage + Blackbox + Debug) - 20 Hz
-- Fusion de diag.lua + testvol.lua en un seul fichier autonome
-- ===================================================================
--
-- SOMMAIRE
--   1. CONFIG              - tous les reglages a un seul endroit
--   2. PERIPHERIQUES        - detection modem/thruster/capteurs
--   3. PID                  - regulateur pour phases CLIMB/CRUISE/TERMINAL
--   4. ESTIMATEUR VITESSE   - delta GPS (le velSensor est peu fiable)
--   5. BLACKBOX              - log texte + export CSV
--   6. GUIDAGE PIQUE         - calcul de commande phase finale
--   7. MODE CALIBRATION      - test au sol du sens yaw/vecteur AVANT de tirer
--   8. MODE DEBUG LIVE       - affichage terminal detaille pendant le vol
--   9. BOUCLE PRINCIPALE     - menu + execution
--
-- ===================================================================

-- ===================================================================
-- 1. CONFIGURATION
-- ===================================================================
local CONFIG = {
    -- Canaux radio
    CANAL_TIR         = 1337,
    CANAL_TELEMETRIE  = 1338,

    -- Sortie redstone pour la detonation
    FACE_EXPLOSIF     = "top",

    -- Duree max de vol avant auto-destruction/arret (secondes)
    MAX_TEMPS_VOL     = 12,

    -- Inversion des axes si le missile part a l'oppose de la cible
    -- (a determiner avec le MODE CALIBRATION, voir section 7)
    INVERSER_X        = false,
    INVERSER_Z        = false,

    -- Distance (m) sous laquelle on considere l'impact
    DISTANCE_IMPACT   = 3.5,

    -- --- Phase MONTEE ---
    -- Amortissement du vecteur de poussee en montee (0 = coupe net, proche de 1 = garde l'elan)
    MONTEE_DECAY      = 0.8,

    -- --- Phase PIQUE (attaque terminale) ---
    PIQUE_GAIN_P      = 0.008,  -- gain proportionnel (reduit vs version d'origine 0.03, qui saturait)
    PIQUE_DAMPING_V   = 0.6,    -- coefficient d'amortissement sur la vitesse estimee
    PIQUE_MAX_BRAQ    = 0.3,    -- braquage max du vecteur de poussee (0-1)
    PIQUE_LISSAGE     = 0.15,   -- filtre passe-bas sur la commande (plus bas = plus lisse)
    DIST_TRANSITION_PIQUE = 15, -- distance horizontale (m) sous laquelle on bascule en PIQUE

    -- --- PID (reserve pour extension CLIMB/CRUISE/TERMINAL avance) ---
    PID_PITCH = { Kp = 0.9, Ki = 0.002, Kd = 0.35, max_out = 1.0 },
    PID_YAW   = { Kp = 0.9, Ki = 0.002, Kd = 0.35, max_out = 1.0 },

    -- Debug
    DEBUG_LIVE_TERMINAL = true,  -- affiche les valeurs cles a chaque tick dans le terminal
    DEBUG_LOG_EVERY_N   = 3,     -- n'affiche qu'un tick sur N pour ne pas saturer l'ecran
}

-- ===================================================================
-- 2. PERIPHERIQUES
-- ===================================================================
local modem = peripheral.find("modem", function(_, o) return o.isWireless() end)
local thruster = peripheral.find("creative_vector_thruster")
              or peripheral.find("vector_thruster")
              or peripheral.find("thruster")

local altSensor  = peripheral.find("altitude_sensor")
local velSensor  = peripheral.find("velocity_sensor")
local gimbSensor = peripheral.find("gimbal_sensor")

if not modem or not thruster then
    error("[-] Composants critiques introuvables (Modem/Thruster)")
end

modem.open(CONFIG.CANAL_TIR)

local function reglerPoussee(valeur)
    if thruster.setPowerNormalized then thruster.setPowerNormalized(valeur)
    elseif thruster.setThrustNormalized then thruster.setThrustNormalized(valeur) end
end

local function reglerVecteur(vx, vz)
    if CONFIG.INVERSER_X then vx = -vx end
    if CONFIG.INVERSER_Z then vz = -vz end

    if thruster.setVector then thruster.setVector(vx, vz)
    else
        if thruster.setVectorX then thruster.setVectorX(vx) end
        if thruster.setVectorY then thruster.setVectorY(vz) end
    end
end

local function couperPropulsion()
    reglerPoussee(0.0)
    reglerVecteur(0.0, 0.0)
    for _, face in ipairs({"top", "bottom", "left", "right", "front", "back"}) do
        redstone.setOutput(face, false)
    end
end

-- ===================================================================
-- 3. PID (disponible pour qui veut affiner CLIMB/CRUISE/TERMINAL)
-- ===================================================================
local function createPID(params)
    return {
        Kp = params.Kp, Ki = params.Ki, Kd = params.Kd, max_out = params.max_out,
        integral = 0, prev_error = 0,

        update = function(self, error, dt)
            if dt <= 0 then return 0 end
            local p = self.Kp * error
            self.integral = self.integral + error * dt
            if self.integral > 2.0 then self.integral = 2.0 end
            if self.integral < -2.0 then self.integral = -2.0 end
            local i = self.Ki * self.integral
            local d = self.Kd * (error - self.prev_error) / dt
            self.prev_error = error
            local output = p + i + d
            if output > self.max_out then output = self.max_out end
            if output < -self.max_out then output = -self.max_out end
            return output
        end,

        reset = function(self)
            self.integral = 0
            self.prev_error = 0
        end
    }
end

-- ===================================================================
-- 4. ESTIMATEUR DE VITESSE PAR DELTA GPS
--    (le velSensor renvoyait 0.00 en permanence dans les logs de vol
--    precedents -> on ne peut pas s'y fier pour l'amortissement)
-- ===================================================================
local function createVelocityEstimator()
    return {
        lastX = nil, lastY = nil, lastZ = nil, lastT = nil,

        update = function(self, x, y, z, t)
            local vx, vy, vz = 0, 0, 0
            if self.lastT and t > self.lastT then
                local dt = t - self.lastT
                vx = (x - self.lastX) / dt
                vy = (y - self.lastY) / dt
                vz = (z - self.lastZ) / dt
            end
            self.lastX, self.lastY, self.lastZ, self.lastT = x, y, z, t
            return vx, vy, vz
        end
    }
end

-- ===================================================================
-- 5. BLACKBOX (log texte + export CSV)
-- ===================================================================
local Blackbox = {
    records = {},      -- lignes texte lisibles (print/dump)
    csvRows  = {},      -- lignes structurees pour export CSV
    max_records = 2000,

    log = function(self, t, phase, pos, vel, gimbal, cmdX, cmdZ, extra)
        extra = extra or {}
        local line = string.format(
            "T:%06.2f | PH:%-8s | POS:[%7.2f,%6.2f,%7.2f] | VEL:[%6.2f,%6.2f,%6.2f] | GIMB:[P:%+05.1f,Y:%+05.1f] | CMD:[X:%+05.3f,Z:%+05.3f] | DIST:%6.1f",
            t, phase,
            pos.x or 0, pos.y or 0, pos.z or 0,
            vel.vx or 0, vel.vy or 0, vel.vz or 0,
            gimbal.pitch or 0, gimbal.yaw or 0,
            cmdX or 0, cmdZ or 0,
            extra.dist or 0
        )
        table.insert(self.records, line)
        if #self.records > self.max_records then table.remove(self.records, 1) end

        table.insert(self.csvRows, {
            t, phase,
            pos.x or 0, pos.y or 0, pos.z or 0,
            vel.vx or 0, vel.vy or 0, vel.vz or 0,
            gimbal.pitch or 0, gimbal.yaw or 0,
            cmdX or 0, cmdZ or 0,
            extra.dist or 0
        })
        if #self.csvRows > self.max_records then table.remove(self.csvRows, 1) end
    end,

    dump = function(self)
        print("==================== EXPORT BLACKBOX ====================")
        for _, line in ipairs(self.records) do print(line) end
        print("=========================================================")
    end,

    dumpCSV = function(self, path)
        local f = fs.open(path, "w")
        if not f then return false end
        f.writeLine("temps,phase,pos_x,pos_y,pos_z,vx,vy,vz,pitch,yaw,cmd_x,cmd_z,dist")
        for _, row in ipairs(self.csvRows) do
            f.writeLine(table.concat(row, ","))
        end
        f.close()
        return true
    end,

    reset = function(self)
        self.records = {}
        self.csvRows = {}
    end
}

-- ===================================================================
-- 6. GUIDAGE PIQUE (phase d'attaque terminale)
-- ===================================================================
local function calculerCommandePique(dx, dz, vx, vz, yaw, currentVecX, currentVecZ)
    local corrX = dx - (vx * CONFIG.PIQUE_DAMPING_V)
    local corrZ = dz - (vz * CONFIG.PIQUE_DAMPING_V)

    local radYaw = math.rad(yaw)
    local localCorrX = corrX * math.cos(radYaw) - corrZ * math.sin(radYaw)
    local localCorrZ = corrX * math.sin(radYaw) + corrZ * math.cos(radYaw)

    local targetVecX = localCorrX * CONFIG.PIQUE_GAIN_P
    local targetVecZ = localCorrZ * CONFIG.PIQUE_GAIN_P

    targetVecX = math.max(-CONFIG.PIQUE_MAX_BRAQ, math.min(CONFIG.PIQUE_MAX_BRAQ, targetVecX))
    targetVecZ = math.max(-CONFIG.PIQUE_MAX_BRAQ, math.min(CONFIG.PIQUE_MAX_BRAQ, targetVecZ))

    local newVecX = currentVecX + (targetVecX - currentVecX) * CONFIG.PIQUE_LISSAGE
    local newVecZ = currentVecZ + (targetVecZ - currentVecZ) * CONFIG.PIQUE_LISSAGE

    return newVecX, newVecZ, targetVecX, targetVecZ
end

-- ===================================================================
-- 7. MODE CALIBRATION (A FAIRE AU SOL AVANT TOUT VOL REEL)
--    Verifie que le sens de INVERSER_X / INVERSER_Z et la convention
--    de rotation yaw correspondent bien a ta config de thruster.
-- ===================================================================
local function modeCalibration()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.cyan)
    print("=== MODE CALIBRATION (missile immobilise / cale) ===")
    term.setTextColor(colors.white)
    print("Objectif : verifier le sens reel du vecteur de poussee")
    print("avant de faire confiance au guidage automatique.\n")
    print("Commandes :")
    print("  x : pousser +X pendant 1s (doit deriver vers +X monde)")
    print("  z : pousser +Z pendant 1s")
    print("  y : lire l'angle yaw actuel du gimbal")
    print("  q : quitter le mode calibration\n")

    while true do
        write("> ")
        local input = read()
        if input == "x" then
            print("[+] Poussee +X (0.2) pendant 1s...")
            reglerVecteur(0.2, 0.0)
            sleep(1)
            reglerVecteur(0.0, 0.0)
            print("    Verifie dans quel sens le missile a derive (log GPS/creative dashboard).")
            print("    Si c'est -X au lieu de +X, mets INVERSER_X = true dans CONFIG.")
        elseif input == "z" then
            print("[+] Poussee +Z (0.2) pendant 1s...")
            reglerVecteur(0.0, 0.2)
            sleep(1)
            reglerVecteur(0.0, 0.0)
            print("    Meme verification pour Z -> INVERSER_Z si besoin.")
        elseif input == "y" then
            if gimbSensor and gimbSensor.getAngles then
                local a = gimbSensor.getAngles()
                print(string.format("    Pitch=%.1f  Yaw=%.1f", a.pitch or 0, a.yaw or 0))
            else
                print("    [!] gimbSensor indisponible.")
            end
        elseif input == "q" then
            break
        else
            print("Commande inconnue.")
        end
    end
end

-- ===================================================================
-- 8. AFFICHAGE DEBUG LIVE (pendant le vol, dans le terminal du missile)
-- ===================================================================
local tickCounter = 0
local function afficherDebugLive(t, phase, cx, cy, cz, dist, vx, vz, yaw, cmdX, cmdZ, targetX, targetZ)
    if not CONFIG.DEBUG_LIVE_TERMINAL then return end
    tickCounter = tickCounter + 1
    if tickCounter % CONFIG.DEBUG_LOG_EVERY_N ~= 0 then return end

    term.setCursorPos(1, 10)
    term.clearLine()
    term.setTextColor(colors.white)
    print(string.format("T:%5.2fs  PH:%-7s  DIST:%6.1fm", t, phase, dist))

    term.clearLine()
    print(string.format("POS  X:%8.2f Y:%7.2f Z:%8.2f", cx, cy, cz))

    term.clearLine()
    print(string.format("VEL  Vx:%6.2f Vz:%6.2f  YAW:%6.1f", vx, vz, yaw))

    term.clearLine()
    term.setTextColor(colors.yellow)
    print(string.format("CMD  X:%+5.3f Z:%+5.3f  (avant lissage X:%+5.3f Z:%+5.3f)", cmdX, cmdZ, targetX or 0, targetZ or 0))

    -- Alerte visuelle si on est en saturation quasi permanente -> signe de gain trop fort
    if math.abs(cmdX) >= CONFIG.PIQUE_MAX_BRAQ - 0.01 or math.abs(cmdZ) >= CONFIG.PIQUE_MAX_BRAQ - 0.01 then
        term.setTextColor(colors.red)
        term.clearLine()
        print("[!] SATURATION - reduire PIQUE_GAIN_P si ca persiste plusieurs secondes")
    end
    term.setTextColor(colors.white)
end

-- ===================================================================
-- 9. BOUCLE PRINCIPALE
-- ===================================================================
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.orange)
print("=== SYSTEME MISSILE UNIFIE ===")
term.setTextColor(colors.white)
print("1. Mode RUN (Lancement Auto dans 3s)")
print("2. Mode MAINTENANCE (Console Shell)")
print("3. Mode CALIBRATION (test vecteurs au sol)")

local timerId = os.startTimer(3)
local choix = nil

while true do
    local event, p1 = os.pullEvent()
    if event == "timer" and p1 == timerId then
        choix = "RUN"
        break
    elseif event == "char" then
        if p1 == "2" then choix = "MAINTENANCE" end
        if p1 == "3" then choix = "CALIBRATION" end
        if choix then break end
        if p1 ~= "1" then
            -- touche non geree, on ignore et on continue d'attendre
        else
            choix = "RUN"
            break
        end
    end
end

if choix == "MAINTENANCE" then
    term.setTextColor(colors.yellow)
    print("\n[!] Passage en Mode MAINTENANCE. Console active.")
    return
elseif choix == "CALIBRATION" then
    modeCalibration()
    print("\n[+] Calibration terminee. Redemarre le script pour lancer un vol.")
    return
end

-- --- MODE RUN ---
while true do
    couperPropulsion()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.lime)
    print("=== MISSILE READY ===")
    term.setTextColor(colors.white)
    print("Capteurs : Alt=" .. (altSensor and "OK" or "NOK") ..
          " | Vit=" .. (velSensor and "OK" or "NOK") ..
          " | Gimbal=" .. (gimbSensor and "OK" or "NOK"))
    print("Inversion axes : X=" .. tostring(CONFIG.INVERSER_X) .. " Z=" .. tostring(CONFIG.INVERSER_Z))
    term.setTextColor(colors.yellow)
    print("\nEn attente d'un ordre de tir sur CH " .. CONFIG.CANAL_TIR .. "...")

    local cibleX, cibleY, cibleZ
    local ALTITUDE_OFFSET = 35

    while true do
        local _, _, chan, _, message = os.pullEvent("modem_message")
        if chan == CONFIG.CANAL_TIR then
            local data = textutils.unserialize(message)
            if data and data.action == "LANCEMENT" then
                cibleX, cibleY, cibleZ = data.x, data.y, data.z
                ALTITUDE_OFFSET = data.altOffset or 35
                term.setTextColor(colors.green)
                print(string.format("\n[+] Ordre recu ! Cible: X:%.1f Y:%.1f Z:%.1f | Survol: +%dm", cibleX, cibleY, cibleZ, ALTITUDE_OFFSET))
                break
            end
        end
    end

    local startX, startY, startZ = gps.locate(2)
    if startX then
        term.setTextColor(colors.red)
        print("=== VOL ACTIF ===")

        Blackbox:reset()
        local startTime = os.clock()
        local altCibleCroisiere = math.max(startY, cibleY) + ALTITUDE_OFFSET
        local phaseVol = "MONTEE"
        local currentVecX, currentVecZ = 0.0, 0.0
        local velEstimator = createVelocityEstimator()
        tickCounter = 0

        reglerPoussee(1.0)

        while true do
            local tempsEcoule = os.clock() - startTime
            local statusActuel = phaseVol

            if tempsEcoule >= CONFIG.MAX_TEMPS_VOL then
                couperPropulsion()
                statusActuel = "ARRET"
            end

            local cx, cy, cz = gps.locate(0.05)
            if altSensor and altSensor.getHeight then
                local altExacte = altSensor.getHeight()
                if altExacte then cy = altExacte end
            end

            if cx then
                local dx, dy, dz = cibleX - cx, cibleY - cy, cibleZ - cz
                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                local dist2D = math.sqrt(dx * dx + dz * dz)

                local vx_est, vy_est, vz_est = velEstimator:update(cx, cy, cz, tempsEcoule)

                if phaseVol == "MONTEE" then
                    if cy >= altCibleCroisiere or dist2D < CONFIG.DIST_TRANSITION_PIQUE then
                        phaseVol = "PIQUE"
                        statusActuel = "PIQUE"
                    end
                end

                if dist <= CONFIG.DISTANCE_IMPACT then
                    statusActuel = "IMPACT"
                end

                local pitch, yaw = 0, 0
                if gimbSensor and gimbSensor.getAngles then
                    local angles = gimbSensor.getAngles()
                    if type(angles) == "table" then
                        pitch = angles.pitch or 0
                        yaw = angles.yaw or 0
                    end
                end

                modem.transmit(CONFIG.CANAL_TELEMETRIE, CONFIG.CANAL_TIR, textutils.serialize({
                    x = cx, y = cy, z = cz, alt = cy,
                    vit = math.sqrt(vx_est*vx_est + vz_est*vz_est), pitch = pitch, yaw = yaw,
                    dist = dist, status = statusActuel
                }))

                if statusActuel == "ARRET" then
                    print("[!] TEMPS DE VOL ECOULE.")
                    break
                elseif statusActuel == "IMPACT" then
                    couperPropulsion()
                    redstone.setOutput(CONFIG.FACE_EXPLOSIF, true)
                    print("[+] DETONATION !")
                    break
                end

                local targetX, targetZ = 0, 0
                if phaseVol == "MONTEE" then
                    currentVecX = currentVecX * CONFIG.MONTEE_DECAY
                    currentVecZ = currentVecZ * CONFIG.MONTEE_DECAY
                    reglerVecteur(currentVecX, currentVecZ)
                    reglerPoussee(1.0)
                else
                    currentVecX, currentVecZ, targetX, targetZ = calculerCommandePique(
                        dx, dz, vx_est, vz_est, yaw, currentVecX, currentVecZ
                    )
                    reglerVecteur(currentVecX, currentVecZ)
                    reglerPoussee(1.0)
                end

                Blackbox:log(
                    tempsEcoule, phaseVol,
                    { x = cx, y = cy, z = cz },
                    { vx = vx_est, vy = vy_est, vz = vz_est },
                    { pitch = pitch, yaw = yaw },
                    currentVecX, currentVecZ,
                    { dist = dist }
                )

                afficherDebugLive(tempsEcoule, phaseVol, cx, cy, cz, dist, vx_est, vz_est, yaw, currentVecX, currentVecZ, targetX, targetZ)
            end
            sleep(0)
        end

        local csvName = "vol_" .. os.date("%Y%m%d_%H%M%S") .. ".csv"
        if Blackbox:dumpCSV(csvName) then
            print("[+] Log CSV sauvegarde : " .. csvName)
        end
    else
        print("[-] PERTE GPS. Tir avorte.")
    end
end
