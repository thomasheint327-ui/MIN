-- ===================================================
-- TÉLÉCOMMANDE GUI
-- Fichier : valise.lua
-- ===================================================

local width, height = term.getSize()
local cibleX, cibleY, cibleZ = 0, 0, 0

local function dessinerEnTete(titre)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.setCursorPos(1, 1)
    term.clearLine()
    local posPad = math.floor((width - #titre) / 2)
    term.setCursorPos(math.max(1, posPad + 1), 1)
    write(titre)
    term.setBackgroundColor(colors.black)
end

local function dessinerBouton(x, y, w, text, bgCol, fgCol)
    term.setBackgroundColor(bgCol)
    term.setTextColor(fgCol)
    term.setCursorPos(x, y)
    write(string.rep(" ", w))
    local textPos = x + math.floor((w - #text) / 2)
    term.setCursorPos(textPos, y)
    write(text)
    term.setBackgroundColor(colors.black)
end

while true do
    term.setBackgroundColor(colors.black)
    term.clear()
    dessinerEnTete("TELECOMMANDE DE VOL")

    -- 1. Récupération & Affichage de la position GPS actuelle
    local curX, curY, curZ = gps.locate(0.5)
    
    term.setCursorPos(2, 3)
    term.setTextColor(colors.yellow)
    write("POSITION ACTUELLE (GPS) :")
    
    term.setCursorPos(3, 4)
    if curX then
        term.setTextColor(colors.lime)
        write(string.format("X: %.1f  Y: %.1f  Z: %.1f", curX, curY, curZ))
    else
        term.setTextColor(colors.red)
        write("Recherche signal GPS...")
    end

    -- 2. Affichage des Coordonnées Cible
    term.setCursorPos(2, 6)
    term.setTextColor(colors.yellow)
    write("CIBLE VERROUILLEE :")
    
    term.setCursorPos(3, 7)
    term.setTextColor(colors.white)
    write(string.format("X: %.1f  Y: %.1f  Z: %.1f", cibleX, cibleY, cibleZ))

    -- 3. Boutons GUI
    dessinerBouton(2, 10, 22, "[ CIBLE GPS (ICI) ]", colors.blue, colors.white)
    dessinerBouton(2, 12, 22, "[ SAISIE MANUELLE ]", colors.purple, colors.white)

    -- Gestion des clics
    local event, button, x, y = os.pullEvent()
    
    if event == "mouse_click" or event == "monitor_touch" then
        
        -- Bouton : CIBLE GPS (ICI)
        if y == 10 then
            local gx, gy, gz = gps.locate(2)
            if gx then
                cibleX, cibleY, cibleZ = gx, gy, gz
            end

        -- Bouton : SAISIE MANUELLE
        elseif y == 12 then
            term.setBackgroundColor(colors.black)
            term.clear()
            dessinerEnTete("SAISIE MANUELLE CIBLE")
            term.setTextColor(colors.cyan)
            term.setCursorPos(2, 4) write("Coordonnee X : ") cibleX = tonumber(read()) or cibleX
            term.setCursorPos(2, 6) write("Coordonnee Y : ") cibleY = tonumber(read()) or cibleY
            term.setCursorPos(2, 8) write("Coordonnee Z : ") cibleZ = tonumber(read()) or cibleZ
        end
    end
end