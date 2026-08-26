-- ===================================================================
-- MISSILE.LUA - GUIDAGE ARC PRECALCULE (CLOSE RANGE) - 20 Hz
-- ===================================================================

-- ===================================================================
-- 1. CONFIGURATION
-- ===================================================================
local CONFIG = {
    CANAL_TIR         = 1337,
    CANAL_TELEMETRIE  = 1338,
    FACE_EXPLOSIF     = "top",
    MAX_TEMPS_VOL     = 15,
    DISTANCE_IMPACT   = 3.5,

    INVERSER_X        = false,
    INVERSER_Z        = false,

    -- --- NOUVELLE PHILOSOPHIE : ARC PRECALCULE ---

    -- Hauteur maximale de l'arc (en blocs) au-dessus de la cible ou du lanceur
    HAUTEUR_ARC       = 25,

    -- Force de l'inclinaison vers l'avant (0.1 = lent, 0.4 = tres rapide/agressif)
    VITESSE_AVANCE    = 0.3,

    -- Puissance de base pour compenser la gravite (a ajuster selon ton mod. Souvent 0.3 a 0.5)
    COMPENSATION_GRAV = 0.4,

    -- Agressivite avec laquelle le missile corrige son altitude pour coller a l'arc
    GAIN_ALTITUDE     = 0.05,

    -- Si true, coupe totalement les moteurs a X metres de la cible pour tomber comme une bombe
    PLONGEON_KINETIC  = true,
    DIST_PLONGEON     = 8,

    -- Debug
    DEBUG_LIVE        = true,
}

-- ===================================================================
-- 2. PERIPHERIQUES
-- ===================================================================
local modem = peripheral.find("modem", function(_, o) return o.isWireless() end)
local thruster = peripheral.find("creative_vector_thruster")
              or peripheral.find("vector_thruster")
              or peripheral.find("thruster")

if not modem or not thruster then
    error("[-] Composants critiques introuvables (Modem/Thruster)")
end

modem.open(CONFIG.CANAL_TIR)

local function reglerPoussee(valeur)
    valeur = math.max(0.0, math.min(1.0, valeur)) -- Clamp entre 0 et 1
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
-- 3. BOUCLE PRINCIPALE
-- ===================================================================
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.orange)
print("=== MISSILE CLOSE-RANGE (ARC) ===")
term.setTextColor(colors.white)

while true do
    couperPropulsion()
    term.setTextColor(colors.lime)
    print("\n=== SYSTEME PRET ===")
    term.setTextColor(colors.yellow)
    print("En attente d'un ordre de tir sur CH " .. CONFIG.CANAL_TIR .. "...")

    local cibleX, cibleY, cibleZ

    -- Attente ordre de tir
    while true do
        local _, _, chan, _, message = os.pullEvent("modem_message")
        if chan == CONFIG.CANAL_TIR then
            local data = textutils.unserialize(message)
            if data and data.action == "LANCEMENT" then
                cibleX, cibleY, cibleZ = data.x, data.y, data.z
                -- Si l'utilisateur donne un altOffset, on l'utilise pour la hauteur de l'arc
                if data.altOffset then CONFIG.HAUTEUR_ARC = data.altOffset end
                term.setTextColor(colors.green)
                print(string.format("[+] Ordre recu ! Cible: [%.1f, %.1f, %.1f]", cibleX, cibleY, cibleZ))
                break
            end
        end
    end

    local startX, startY, startZ = gps.locate(2)
    if startX then
        term.setTextColor(colors.red)
        print("=== DECOLLAGE ===")

        local startTime = os.clock()

        -- PRECALCUL DE LA TRAJECTOIRE
        -- On calcule la distance horizontale totale à parcourir
        local dx0 = cibleX - startX
        local dz0 = cibleZ - startZ
        local distInitiale = math.sqrt(dx0*dx0 + dz0*dz0)
        distInitiale = math.max(1, distInitiale) -- evite div par 0

        local tickCounter = 0

        -- Boucle de vol
        while true do
            local t = os.clock() - startTime
            if t >= CONFIG.MAX_TEMPS_VOL then
                print("[!] TEMPS DE VOL ECOULE.")
                break
            end

            local cx, cy, cz = gps.locate(0.05)
            if cx then
                -- 1. Calcul de la progression (0.0 au depart, 1.0 a la cible)
                local dx = cibleX - cx
                local dz = cibleZ - cz
                local distActuelle = math.sqrt(dx*dx + dz*dz)

                local progression = 1.0 - (distActuelle / distInitiale)
                progression = math.max(0.0, math.min(1.0, progression)) -- borne entre 0 et 1

                -- 2. VERIFICATION IMPACT
                if distActuelle <= CONFIG.DISTANCE_IMPACT or (progression > 0.95 and math.abs(cy - cibleY) < 3) then
                    couperPropulsion()
                    redstone.setOutput(CONFIG.FACE_EXPLOSIF, true)
                    term.setTextColor(colors.red)
                    print("\n[+] BOOM ! IMPACT CONFIRME.")
                    break
                end

                -- 3. CALCUL DE L'ALTITUDE PRECALCULEE (L'Arc)
                -- Interpolation lineaire entre l'altitude de depart et d'arrivee
                local baseAlt = startY + (cibleY - startY) * progression
                -- Ajout de la courbe en cloche (sinus: 0 au depart, 1 a mi-chemin, 0 a l'arrivee)
                local altIdeale = baseAlt + (CONFIG.HAUTEUR_ARC * math.sin(progression * math.pi))

                -- 4. CORRECTION MOTEUR (Monter ou Descendre)
                local erreurY = altIdeale - cy
                local thrust = CONFIG.COMPENSATION_GRAV + (erreurY * CONFIG.GAIN_ALTITUDE)

                -- 5. DIRECTION HORIZONTALE
                local vecX = (dx / distActuelle) * CONFIG.VITESSE_AVANCE
                local vecZ = (dz / distActuelle) * CONFIG.VITESSE_AVANCE

                -- 6. PHASE TERMINALE (Plongeon final)
                local status = "EN VOL"
                if CONFIG.PLONGEON_KINETIC and distActuelle < CONFIG.DIST_PLONGEON then
                    status = "PLONGEON!"
                    thrust = 0.0 -- Coupe les gaz pour tomber net
                    vecX = 0.0
                    vecZ = 0.0
                end

                -- Application
                reglerVecteur(vecX, vecZ)
                reglerPoussee(thrust)

                -- Telemetrie & Affichage
                tickCounter = tickCounter + 1
                if tickCounter % 3 == 0 and CONFIG.DEBUG_LIVE then
                    term.setCursorPos(1, 8)
                    term.clearLine()
                    term.setTextColor(colors.white)
                    print(string.format("DIST: %5.1f m | PROG: %3.0f%% | %s", distActuelle, progression*100, status))

                    term.clearLine()
                    print(string.format("ALT Actuelle: %5.1f | ALT Prevue: %5.1f", cy, altIdeale))

                    term.clearLine()
                    term.setTextColor(colors.yellow)
                    print(string.format("VECT: X%+.2f Z%+.2f | GAZ: %3.0f%%", vecX, vecZ, thrust*100))
                end
            end
            sleep(0)
        end
    else
        print("[-] PERTE GPS. Tir avorte.")
    end

    term.setTextColor(colors.gray)
    print("\nReinitialisation dans 3 secondes...")
    sleep(3)
    term.clear()
end