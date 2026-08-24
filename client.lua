local modem = peripheral.find("modem")
if not modem then error("Pas de modem !") end

local CONFIG = {
    sharedSecret = "OMEGA_GHOST_2026", -- Doit être IDENTIQUE à la base
    hopInterval = 10 -- Doit être IDENTIQUE à la base
}

-- La même fonction de hachage que la base
local function simpleHash(str)
    local h = 5381
    for i = 1, #str do h = (h * 33 + string.byte(str, i)) % 4294967296 end
    return h
end

-- Calcul de la fréquence actuelle
local function getHoppingChannel()
    local timeWindow = math.floor(os.epoch("utc") / 1000 / CONFIG.hopInterval)
    local seed = simpleHash(CONFIG.sharedSecret .. tostring(timeWindow))
    math.randomseed(seed)
    return math.random(10000, 60000)
end

-- On trouve la fréquence secrète
local targetChannel = getHoppingChannel()

print("Recherche de la base sur le canal fantome : " .. targetChannel)

-- On envoie le message !
local message_secret = "ORDRE_DE_LANCEMENT_AUTORISE"
modem.transmit(targetChannel, targetChannel, message_secret)

term.setTextColor(colors.green)
print("Paquet envoye avec succes en toute furtivite.")
term.setTextColor(colors.white)