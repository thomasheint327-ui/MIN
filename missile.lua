-- ============================================================================
-- MISSILE.LUA - TEST ACCÉLÉRATION / DÉCÉLÉRATION (20 SECONDES)
-- ============================================================================

local motor = peripheral.find("Create_CreativeMotor")

if not motor then
    print("[ERREUR] Aucun 'Create_CreativeMotor' trouve.")
    return
end

local MAX_SPEED      = 128  -- Vitesse maximale atteinte (RPM)
local TIME_ACCEL     = 10   -- Durée d'accélération (secondes)
local TIME_DECEL     = 10   -- Durée de décélération (secondes)
local TICK_INTERVAL  = 0.05 -- Fréquence de rafraîchissement (20Hz)

term.clear()
term.setCursorPos(1, 1)
print("========================================")
print(" TEST MOTEUR : ACCEL / DECEL (20s)")
print(" Moteur : " .. peripheral.getName(motor))
print("========================================")

-- ----------------------------------------------------------------------------
-- PHASE 1 : ACCÉLÉRATION (0 -> MAX_SPEED en 10s)
-- ----------------------------------------------------------------------------
print("\n--> Phase 1 : Acceleration (10s)")
local steps_accel = TIME_ACCEL / TICK_INTERVAL

for i = 0, steps_accel do
    local progress = i / steps_accel
    local speed    = progress * MAX_SPEED
    
    motor.setGeneratedSpeed(speed)
    
    term.setCursorPos(1, 7)
    term.clearLine()
    write(string.format("Vitesse: %5.1f RPM | Temps: %4.1fs / %ds", speed, i * TICK_INTERVAL, TIME_ACCEL))
    
    sleep(TICK_INTERVAL)
end

-- ----------------------------------------------------------------------------
-- PHASE 2 : DÉCÉLÉRATION (MAX_SPEED -> 0 en 10s)
-- ----------------------------------------------------------------------------
print("\n\n--> Phase 2 : Deceleration (10s)")
local steps_decel = TIME_DECEL / TICK_INTERVAL

for i = 0, steps_decel do
    local progress = i / steps_decel
    local speed    = MAX_SPEED * (1 - progress)
    
    motor.setGeneratedSpeed(speed)
    
    term.setCursorPos(1, 11)
    term.clearLine()
    write(string.format("Vitesse: %5.1f RPM | Temps: %4.1fs / %ds", speed, i * TICK_INTERVAL, TIME_DECEL))
    
    sleep(TICK_INTERVAL)
end

-- Sécurité finale
motor.setGeneratedSpeed(0)

term.setCursorPos(1, 13)
print("\n[SUCCES] Test de 20s termine. Moteur arrete a 0 RPM.")