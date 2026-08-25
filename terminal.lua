local modem = peripheral.find("modem")
if not modem then error("Modem introuvable !") end

local CANAL_TIR = 1337

-- Fonction pour dessiner l'interface
local function drawHeader()
    term.setBackgroundColor(colors.black)
    term.clear()
    
    -- Barre de titre
    term.setCursorPos(1,1)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.yellow)
    term.clearLine()
    print("=== COMMANDEMENT TACTIQUE ===")
    term.setBackgroundColor(colors.black)
end

-- Fonction pour demander une coordonnée
local function askCoord(nom, ligne)
    term.setCursorPos(2, ligne)
    term.setTextColor(colors.lightBlue)
    write("Cible " .. nom .. " : ")
    term.setTextColor(colors.white)
    local val = tonumber(read())
    return val
end

-- Boucle principale de l'interface
while true do
    drawHeader()
    term.setCursorPos(2, 3)
    term.setTextColor(colors.white)
    print("Entrez les coordonnees :")

    local cx = askCoord("X", 5)
    local cy = askCoord("Y", 6)
    local cz = askCoord("Z", 7)

    -- Vérification que tu as bien tapé des nombres
    if cx and cy and cz then
        term.setCursorPos(2, 9)
        term.setTextColor(colors.red)
        write("CONFIRMER LE TIR ? (o/n) ")
        local conf = read()
        
        if conf == "o" or conf == "O" then
            term.setCursorPos(2, 11)
            term.setTextColor(colors.green)
            print("[!] TRANSMISSION ORDRE [!]")
            
            -- On emballe les coordonnées dans un "paquet" (table)
            local payload = {action="LANCEMENT", x=cx, y=cy, z=cz}
            
            -- On envoie la table convertie en texte
            modem.transmit(CANAL_TIR, CANAL_TIR, textutils.serialize(payload))
            
            sleep(3)
        end
    else
        term.setCursorPos(2, 9)
        term.setTextColor(colors.red)
        print("Erreur : Nombres invalides.")
        sleep(2)
    end
end