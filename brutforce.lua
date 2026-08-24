local modem = peripheral.find("modem")
if not modem then error("Pas de modem !") end

local CANAL_RETOUR = 65000 -- Notre canal d'écoute secret pour le radar
modem.open(CANAL_RETOUR)

term.clear()
term.setCursorPos(1,1)
term.setTextColor(colors.red)
print("=== SONAR ACTIF LANCE ===")
term.setTextColor(colors.yellow)
print("Bombardement des 65535 canaux en cours...")

-- 1. PHASE DE BRUTE FORCE (BOMBARDEMENT)
for canal = 1, 65535 do
    -- On envoie un paquet qui ressemble à une commande système
    -- En espérant que la cible essaie d'y répondre !
    modem.transmit(canal, CANAL_RETOUR, {cmd="PING", auth="ADMIN"})
    
    -- Pause microscopique tous les 1000 messages pour ne pas faire
    -- crasher notre propre ordinateur sous la charge de calcul.
    if canal % 1000 == 0 then sleep(0) end 
end

term.setTextColor(colors.green)
print("Balayage termine. Ecoute de l'echo radar (5 secondes)...")
term.setTextColor(colors.white)

-- 2. PHASE D'ÉCOUTE RADAR (INTERCEPTION DES RÉPONSES)
local timer = os.startTimer(5) -- On écoute pendant 5 secondes

while true do
    local event, side, repCanal, replyChannel, message, distance = os.pullEvent()
    
    if event == "modem_message" then
        term.setTextColor(colors.purple)
        print("[!] CIBLE DETECTEE [!]")
        term.setTextColor(colors.white)
        print(" -> Distance  : " .. math.floor(distance) .. " blocs")
        print(" -> Message   : " .. tostring(message))
        
    elseif event == "timer" and side == timer then
        term.setTextColor(colors.gray)
        print("Fin du scan. Aucune autre cible n'a mordu a l'hamecon.")
        break
    end
end

modem.close(CANAL_RETOUR)