-- ============================================================================
-- SYSTEME DE GUIDAGE MISSILE AVEC BLACKBOX & TRAJECTOIRE MONTEE-DESCENTE
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. CONFIGURATION & REGLAGES (A ajuster selon les données Blackbox)
-- ----------------------------------------------------------------------------
local CONFIG = {
    -- Gains PID pour le Pitch (Profondeur) et Yaw (Lacet)
    -- Conseil : Réduire Kp si oscillation, augmenter Kd pour amortir
    PID_PITCH = { Kp = 1.6, Ki = 0.005, Kd = 0.45, max_out = 1.0 },
    PID_YAW   = { Kp = 1.6, Ki = 0.005, Kd = 0.45, max_out = 1.0 },

    -- Paramètres de Trajectoire (Montée - Descente)
    T_BOOST          = 1.2,   -- Durée initiale du boost (secondes)
    CLIMB_PITCH_DEG  = 35.0,  -- Angle de montée en diagonale (degrés)
    LOFT_ALTITUDE    = 250.0, -- Altitude max atteinte en montée (mètres)
    CRUISE_ALTITUDE  = 180.0, -- Altitude de transition/croisière (mètres)
    DIST_TERMINAL    = 350.0, -- Distance du piqué terminal vers la cible (m)

    -- Filtrage des commandes (Lissage passe-bas)
    SMOOTHING_FACTOR = 0.80,  -- 0.0 = pas de lissage, 0.9 = très lissé
}

-- ----------------------------------------------------------------------------
-- 2. DUCTUS / STRUCTURE REGULATEUR PID
-- ----------------------------------------------------------------------------
local function createPID(params)
    return {
        Kp = params.Kp,
        Ki = params.Ki,
        Kd = params.Kd,
        max_out = params.max_out,
        integral = 0,
        prev_error = 0,
        
        update = function(self, error, dt)
            if dt <= 0 then return 0 end
            
            -- Terme Proportionnel
            local p = self.Kp * error
            
            -- Terme Intégral avec Anti-Windup
            self.integral = self.integral + error * dt
            if self.integral > 2.0 then self.integral = 2.0 end
            if self.integral < -2.0 then self.integral = -2.0 end
            local i = self.Ki * self.integral
            
            -- Terme Dérivé (Amortissement des oscillations)
            local d = self.Kd * (error - self.prev_error) / dt
            self.prev_error = error
            
            -- Commande brute
            local output = p + i + d
            
            -- Clamping (Saturation)
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

-- ----------------------------------------------------------------------------
-- 3. BOITE NOIRE (BLACKBOX LOGGER)
-- ----------------------------------------------------------------------------
local Blackbox = {
    records = {},
    max_records = 1500,
    
    log = function(self, time, phase, pos, attitude, vel, cmd, errors)
        local line = string.format(
            "T:%06.2f | PH:%-8s | POS:[%6.1f,%6.1f,%6.1f] | ATT:[P:%+05.1f°,Y:%+05.1f°] | VEL:[%5.1f,%5.1f,%5.1f] | CMD:[P:%+04.2f,Y:%+04.2f] | ERR:[P:%+04.2f,Y:%+04.2f]",
            time,
            phase,
            pos.x or 0, pos.y or 0, pos.z or 0,
            math.deg(attitude.pitch or 0), math.deg(attitude.yaw or 0),
            vel.vx or 0, vel.vy or 0, vel.vz or 0,
            cmd.pitch or 0, cmd.yaw or 0,
            math.deg(errors.pitch or 0), math.deg(errors.yaw or 0)
        )
        table.insert(self.records, line)
        if #self.records > self.max_records then
            table.remove(self.records, 1)
        end
    end,
    
    dump = function(self)
        print("==================== EXPORT BLACKBOX ====================")
        for _, line in ipairs(self.records) do
            print(line)
        end
        print("=========================================================")
    end
}

-- ----------------------------------------------------------------------------
-- 4. CONTROLEUR DE GUIDAGE DU MISSILE
-- ----------------------------------------------------------------------------
local MissileController = {
    phase = "BOOST",
    time_elapsed = 0,
    
    pid_pitch = createPID(CONFIG.PID_PITCH),
    pid_yaw   = createPID(CONFIG.PID_YAW),
    
    last_cmd_pitch = 0,
    last_cmd_yaw   = 0,

    update = function(self, dt, pos, attitude, vel, target_pos)
        self.time_elapsed = self.time_elapsed + dt
        
        -- Distances relatives
        local dx = target_pos.x - pos.x
        local dy = target_pos.y - pos.y
        local dz = target_pos.z - pos.z
        local dist_horiz = math.sqrt(dx*dx + dy*dy)
        local dist_3d    = math.sqrt(dx*dx + dy*dy + dz*dz)
        
        -- Cap cible (Yaw)
        local target_yaw = math.atan2(dy, dx)
        local target_pitch = 0
        
        -- --------------------------------------------------------------------
        -- LOGIQUE DES PHASES (Machine à états)
        -- --------------------------------------------------------------------
        if self.time_elapsed < CONFIG.T_BOOST then
            self.phase = "BOOST"
            target_pitch = math.rad(10.0) -- Légère montée initiale pour s'éjecter

        elseif dist_3d <= CONFIG.DIST_TERMINAL then
            self.phase = "TERMINAL"
            -- Phase Terminale : Piqué direct sur la cible
            target_pitch = math.atan2(dz, dist_horiz)

        elseif pos.z < CONFIG.LOFT_ALTITUDE and dist_horiz > CONFIG.DIST_TERMINAL then
            self.phase = "CLIMB"
            -- Phase Montée Diagonale
            target_pitch = math.rad(CONFIG.CLIMB_PITCH_DEG)

        else
            self.phase = "CRUISE"
            -- Phase Croisière Descendante vers la cible
            local alt_diff = CONFIG.CRUISE_ALTITUDE - pos.z
            local desired_angle = math.atan2(alt_diff, dist_horiz)
            
            -- Bornage raisonnable de l'angle en croisière (-20° à +10°)
            target_pitch = math.max(math.rad(-20.0), math.min(math.rad(10.0), desired_angle))
        end

        -- --------------------------------------------------------------------
        -- ERREURS D'ATTITUDE & NORMALISATION
        -- --------------------------------------------------------------------
        local err_pitch = target_pitch - attitude.pitch
        local err_yaw   = target_yaw - attitude.yaw
        
        -- Normalisation du Yaw (-PI à +PI)
        while err_yaw > math.pi  do err_yaw = err_yaw - 2*math.pi end
        while err_yaw < -math.pi do err_yaw = err_yaw + 2*math.pi end

        -- --------------------------------------------------------------------
        -- CALCUL PID & LISSAGE DES COMMANDES
        -- --------------------------------------------------------------------
        local raw_cmd_pitch = self.pid_pitch:update(err_pitch, dt)
        local raw_cmd_yaw   = self.pid_yaw:update(err_yaw, dt)
        
        -- Filtre passe-bas (Lissage)
        local alpha = 1.0 - CONFIG.SMOOTHING_FACTOR
        local cmd_pitch = self.last_cmd_pitch * CONFIG.SMOOTHING_FACTOR + raw_cmd_pitch * alpha
        local cmd_yaw   = self.last_cmd_yaw * CONFIG.SMOOTHING_FACTOR + raw_cmd_yaw * alpha
        
        self.last_cmd_pitch = cmd_pitch
        self.last_cmd_yaw   = cmd_yaw

        -- --------------------------------------------------------------------
        -- ENREGISTREMENT BLACKBOX
        -- --------------------------------------------------------------------
        Blackbox:log(
            self.time_elapsed,
            self.phase,
            pos,
            attitude,
            vel,
            { pitch = cmd_pitch, yaw = cmd_yaw },
            { pitch = err_pitch, yaw = err_yaw }
        )

        return cmd_pitch, cmd_yaw
    end
}

-- Exposer le contrôleur et la Blackbox pour l'environnement hôte
return {
    controller = MissileController,
    blackbox = Blackbox,
    config = CONFIG
}