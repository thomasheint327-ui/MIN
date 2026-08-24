local modem = peripheral.find("modem")
if not modem then error("Pas de modem !") end

local CONFIG = {
    sharedSecret = "OMEGA_GHOST_2026",
    hopInterval = 10
}

local function simpleHash(str)
    local h = 5381
    for i = 1, #str do h = (h * 33 + string.byte(str, i)) % 4294967296 end
    return h
end

local function getHoppingChannel()
    local timeWindow = math.floor(os.epoch("utc") / 1000 / CONFIG.hopInterval)
    local seed = simpleHash(CONFIG.sharedSecret .. tostring(timeWindow))
    math.randomseed(seed)
    return math.random(10000, 60000)
end

term.clear()
term.setCursorPos(1,1)
term.setTextColor(colors.green)
print("=== TERMINAL FANTOME CONNECTE ===")
print("Tape 'exit' pour quitter.")
print("---------------------------------")

-- La boucle interactive
while true do
    term.setTextColor(colors.white)
    write("Commande > ")
    local input = read() -- Attend que tu tapes quelque chose
    
    if input == "exit" then
        print("Deconnexion...")
        break
    end
    
    if input ~= "" then
        local targetChannel = getHoppingChannel()
        modem.transmit(targetChannel, targetChannel, input)
        
        term.setTextColor(colors.gray)
        print("[!] Envoye sur le canal " .. targetChannel)
    end
end