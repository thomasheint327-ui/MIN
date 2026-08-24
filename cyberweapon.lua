-- ============================================================
-- APEX FIREWALL v4 — GHOST PROTOCOL (PURE SOFT-WARFARE)
-- CC:Tweaked - Saut de Fréquence & Event Queue Overflow
-- ============================================================

local modem = peripheral.find("modem")
if not modem then error("ERREUR : Aucun modem detecte.") end

local CONFIG = {
    sharedSecret = "OMEGA_GHOST_2026",
    hopInterval = 10, -- Change de canal toutes les 10 secondes
    honeypotChannels = { 80, 443, 666, 8080 }, -- Pièges classiques
    counterAttackDuration = 5,
}

local running = true
local currentChannel = 0
local activeTargets = {}

-- ============================================================
-- MOTEUR CRYPTOGRAPHIQUE & SAUT DE FRÉQUENCE
-- ============================================================

local function simpleHash(str)
    local h = 5381
    for i = 1, #str do h = (h * 33 + string.byte(str, i)) % 4294967296 end
    return h
end

-- Calcule le canal secret actuel (Synchronisé avec tes clients)
local function getHoppingChannel()
    local timeWindow = math.floor(os.epoch("utc") / 1000 / CONFIG.hopInterval)
    local seed = simpleHash(CONFIG.sharedSecret .. tostring(timeWindow))
    math.randomseed(seed)
    return math.random(10000, 60000) -- Se cache dans les hautes fréquences
end

-- ============================================================
-- GESTIONNAIRE DE RÉSEAU (LE FANTÔME)
-- ============================================================

local function hoppingThread()
    while running do
        local newChannel = getHoppingChannel()
        if newChannel ~= currentChannel then
            if currentChannel ~= 0 then modem.close(currentChannel) end
            currentChannel = newChannel
            modem.open(currentChannel)
            -- term.setTextColor(colors.gray)
            -- print("[GHOST] Saut vers frequence cachee : " .. currentChannel)
        end
        sleep(1) -- Vérifie chaque seconde si la fenêtre de 10s est passée
    end
end

-- ============================================================
-- CONTRE-ATTAQUE LOGICIELLE (LE POISON)
-- ============================================================

local function engageTarget(targetChannel)
    if targetChannel == nil or targetChannel == 0 then return end
    if not activeTargets[targetChannel] then
        activeTargets[targetChannel] = (os.epoch("utc") / 1000) + CONFIG.counterAttackDuration
        term.setTextColor(colors.red)
        print("[!] SOFT-KILL LANCE SUR LE CANAL : " .. targetChannel)
    end
end

-- Vise à provoquer l'erreur "Too many events" chez le hacker
local function softKillThread()
    -- On crée un "paquet lourd" pour ralentir le parsage du hacker
    local poisonPacket = string.rep("X", 8192) -- 8KB de données inutiles
    
    while running do
        local fire = false
        local current = os.epoch("utc") / 1000
        
        for target, expiry in pairs(activeTargets) do
            if current > expiry then
                activeTargets[target] = nil
            else
                -- Tir ultra-rapide pour saturer la file d'attente CC
                modem.transmit(target, target, poisonPacket)
                fire = true
            end
        end
        
        if fire then sleep(0) else sleep(0.5) end
    end
end

-- ============================================================
-- ÉCOUTE ET TRAITEMENT
-- ============================================================

local function networkThread()
    while running do
        local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")

        -- 1. HONEYPOT : Si quelqu'un scanne les ports standards, on le frappe.
        local isHoneypot = false
        for _, hp in ipairs(CONFIG.honeypotChannels) do
            if channel == hp then isHoneypot = true break end
        end

        if isHoneypot then
            term.setTextColor(colors.yellow)
            print("[ALERT] Scan ennemi detecte ! Cible: " .. tostring(replyChannel))
            engageTarget(replyChannel)
        
        -- 2. CANAL LÉGITIME : On ne traite que sur la bonne fréquence du moment
        elseif channel == currentChannel then
            -- Optionnel : Tu peux remettre ici la vérification du token auth (V3)
            -- Mais le simple fait de trouver ce canal aléatoire est déjà une preuve de confiance.
            term.setTextColor(colors.green)
            print("[OK] Paquet valide recu : " .. tostring(message))
        end
    end
end

-- ============================================================
-- INITIALISATION
-- ============================================================

term.clear()
term.setCursorPos(1,1)
term.setTextColor(colors.purple)
print("========================================")
print("  V4 GHOST PROTOCOL - SOFT WARFARE LANCE")
print("========================================")

-- Ouverture des pièges
for _, hp in ipairs(CONFIG.honeypotChannels) do modem.open(hp) end

parallel.waitForAll(hoppingThread, networkThread, softKillThread)