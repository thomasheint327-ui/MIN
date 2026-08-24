local modem = peripheral.find("modem")
if not modem then error("Pas de modem !") end

local CANAL_RETOUR = 65000
modem.open(CANAL_RETOUR)

term.clear()
term.setCursorPos(1,1)
term.setTextColor(colors.red)
print("=== SONAR ACTIF CONTINU LANCE ===")
term.setTextColor(colors.gray)
print("Appuie sur Ctrl+T pour forcer l'arret.")
print("-----------------------------------")

local cibleTrouvee = false

-- Boucle infinie tant qu'on n'a pas de cible
while not cibleTrouvee do
    term.setTextColor(colors.yellow)
    print("[*] Balayage des 65535 canaux en cours...")

    -- 1. PHASE DE PING (BOMBARDEMENT)
    for canal = 1, 65535 do
        modem.transmit(canal, CANAL_RETOUR, {cmd="PING", auth="ADMIN"})
        if canal % 1000 == 0 then sleep(0) end 
    end

    term.setTextColor(colors.cyan)
    print("[*] Ecoute de l'echo (3 secondes)...")

    -- 2. PHASE D'ÉCOUTE
    local timer = os.startTimer(3) -- On écoute 3 secondes pour aller plus vite
    local listening = true

    while listening do
        local event, side, repCanal, replyChannel, message, distance = os.pullEvent()
        
        if event == "modem_message" then
            -- CIBLE TROUVÉE !
            term.setTextColor(colors.purple)
            print("\n[!] CIBLE DETECTEE [!]")
            term.setTextColor(colors.white)
            print(" -> Distance  : " .. math.floor(distance) .. " blocs")
            print(" -> Canal rep : " .. tostring(replyChannel))
            print(" -> Message   : " .. tostring(message))
            
            -- On casse les deux boucles
            cibleTrouvee = true
            listening = false 
            
        elseif event == "timer" and side == timer then
            -- RIEN TROUVÉ, ON RECOMMENCE
            term.setTextColor(colors.gray)
            print("[-] Echo vide. Relance du radar...\n")
            listening = false -- On sort de l'écoute pour relancer le grand balayage
        end
    end
end

modem.close(CANAL_RETOUR)
term.setTextColor(colors.green)
print("\n[+] Fin de la traque. Cible verrouillee.")