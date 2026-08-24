local modem = peripheral.find("modem")
if not modem then error("Pas de modem !") end

term.clear()
term.setTextColor(colors.red)
print("=== BROUILLEUR HAUTE DENSITE ===")
print("Statut : EMISSION CONTINUE")

-- On crée un paquet "lourd" pour ralentir son traitement s'il essaie de le lire
local bruit = string.rep("0xDEADBEEF_JAMMING_SIGNAL_", 50)

while true do
    -- On arrose 500 canaux d'un coup, le plus vite possible
    for canal = 1, 65535 do
        modem.transmit(canal, 0, bruit)
        
        -- On fait une pause d'un tick (20Hz) tous les 100 envois 
        -- pour ne pas faire crasher NOTRE propre brouilleur
        if canal % 100 == 0 then
            sleep(0) 
        end
    end
end