-- =======================================
-- VOL D'ESSAI GPS (LIMITE 4 SECONDES)
-- =======================================

-- Coordonnees cibles pour le test
local CIBLE_X = 500
local CIBLE_Y = 100
local CIBLE_Z = -250

local modem = peripheral.find("modem")
if not modem then error("Modem requis pour capter le GPS !") end

-- Fonction de sécurité absolue
local function couperMoteurs()
    for _, face in ipairs(rs.getSides()) do
        rs.setAnalogOutput(face, 0)
    end
end

-- On s'assure que tout est éteint avant le lancement
couperMoteurs()

term.clear()
term.setTextColor(colors.orange)
print("=== PROTOCOLE DE TEST ===")
print("Acquisition du signal GPS...")

-- Vérification du GPS avant la mise à feu
local x, y, z = gps.locate(2)
if not x then
    term.setTextColor(colors.red)
    print("ECHEC : Aucun signal GPS recu. Lancement annule.")
    return
end

term.setTextColor(colors.green)
print("GPS OK. MISE A FEU !")
sleep(1) -- Laisse 1 seconde pour reculer si tu es à côté

-- Enregistre l'heure exacte (en secondes) du décollage
local startTime = os.clock()

-- Boucle de vol
while true do
    -- Calcul du temps écoulé
    local tempsEcoule = os.clock() - startTime
    
    -- 1. LE COUPE-CIRCUIT (LA SECURITE)
    if tempsEcoule >= 4 then
        term.setTextColor(colors.red)
        print("\n[!] 4 SECONDES ECOULEES [!]")
        print("Mise hors tension des moteurs.")
        couperMoteurs()
        break -- On sort de la boucle, le programme s'arrête
    end

    -- 2. LE VOL (si on est sous les 4 secondes)
    local cx, cy, cz = gps.locate(1)
    
    if cx then
        -- Affichage du chrono sur l'écran
        term.setCursorPos(1, 5)
        term.setTextColor(colors.white)
        print("Temps de vol : " .. string.format("%.1f", tempsEcoule) .. "s / 4.0s  ")
        
        -- Allumage du propulseur principal arrière
        rs.setAnalogOutput("back", 15) 

        -- Gestion simplifiée de l'altitude pour le test
        local dy = CIBLE_Y - cy
        if dy > 2 then
            rs.setAnalogOutput("bottom", 15) -- Pousse vers le haut
        else
            rs.setAnalogOutput("bottom", 0)  -- Coupe la poussée verticale
        end
        
        -- (Les corrections X/Z sont ignorées pour ce premier test de ligne droite)
    else
        term.setTextColor(colors.orange)
        print("Perte GPS, vol a l'aveugle...")
    end
    
    sleep(0.1) -- Met à jour les moteurs 10 fois par seconde
end

term.setTextColor(colors.gray)
print("\nFin du test. Recuperation possible.")