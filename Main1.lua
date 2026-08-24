-- ===================================================
-- VERROUILLAGE MISSILE — Identification par position de lancement
-- ===================================================

-- Détection automatique des périphériques
local monitor = peripheral.find("monitor")
local radar = peripheral.find("create_radar:radar_bearing")

if not radar then
    for _, name in ipairs(peripheral.getNames()) do
        if name:find("radar") then
            radar = peripheral.wrap(name)
            break
        end
    end
end

if not monitor then error("Erreur : Aucun ecran trouve sur le reseau !") end
if not radar then error("Erreur : Aucun radar trouve sur le reseau !") end

-- ===================================================
-- CONFIGURATION — A adapter selon ta rampe de lancement
-- ===================================================
local LAUNCH_POS = { x = 460, y = 43, z = 34 }  -- Coordonnees de la rampe de tir
local LOCK_RADIUS = 15                        -- Distance max (blocs) pour considerer un SABLE comme "au lancement"

-- Calcule la distance 3D entre deux positions
local function distance(a, b)
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Recupere tous les SABLE actuellement detectes
local function getSableTracks()
    local ok, tracks = pcall(function() return radar.getTracks() end)
    if not ok or not tracks then return {} end

    local sables = {}
    for _, track in ipairs(tracks) do
        if track.category == "SABLE" then
            table.insert(sables, track)
        end
    end
    return sables
end

-- ===================================================
-- ECRAN
-- ===================================================
term.redirect(monitor)
monitor.setTextScale(0.5)
monitor.setBackgroundColor(colors.black)

local function drawHeader(title)
    monitor.clear()
    term.setCursorPos(1, 1)
    monitor.setTextColor(colors.green)
    print(title)
    print("-------------------------------")
end

-- ===================================================
-- PHASE 1 : VERROUILLAGE — trouve le missile pres de la rampe
-- ===================================================
local lockedId = nil
local lockedPos = nil

drawHeader("=== RECHERCHE DU MISSILE ===")
monitor.setTextColor(colors.yellow)
print("En attente d'un SABLE pres de")
print(string.format("la rampe (X:%d Y:%d Z:%d)", LAUNCH_POS.x, LAUNCH_POS.y, LAUNCH_POS.z))
print(string.format("Rayon de verrouillage : %d blocs", LOCK_RADIUS))
print("")

while not lockedId do
    local sables = getSableTracks()
    local best, bestDist = nil, math.huge

    for _, track in ipairs(sables) do
        local d = distance(track.position, LAUNCH_POS)
        if d < LOCK_RADIUS and d < bestDist then
            best = track
            bestDist = d
        end
    end

    if best then
        lockedId = best.id
        lockedPos = { x = best.position.x, y = best.position.y, z = best.position.z }

        monitor.setTextColor(colors.lime)
        print(">> MISSILE VERROUILLE <<")
        print("ID  : " .. lockedId:sub(1, 8))
        print(string.format("POS : X:%.1f Y:%.1f Z:%.1f", lockedPos.x, lockedPos.y, lockedPos.z))
        sleep(2)
    else
        sleep(0.5)
    end
end

-- ===================================================
-- PHASE 2 : SUIVI CONTINU DU MISSILE VERROUILLE
-- ===================================================
while true do
    local sables = getSableTracks()
    local found = nil

    for _, track in ipairs(sables) do
        if track.id == lockedId then
            found = track
            break
        end
    end

    drawHeader("=== SUIVI MISSILE (LOCKED) ===")
    monitor.setTextColor(colors.orange)
    print("ID : " .. lockedId:sub(1, 8))
    print("-------------------------------")

    if found then
        local pos = found.position
        local vel = found.velocity

        monitor.setTextColor(colors.white)
        print(string.format("POS : X:%.1f", pos.x))
        print(string.format("      Y:%.1f", pos.y))
        print(string.format("      Z:%.1f", pos.z))

        monitor.setTextColor(colors.lightGray)
        print(string.format("VEL : X:%.1f Y:%.1f Z:%.1f", vel.x, vel.y, vel.z))

        -- Distance parcourue depuis le point de lancement
        local traveled = distance(pos, lockedPos)
        monitor.setTextColor(colors.cyan)
        print(string.format("DIST DEPUIS LANCEMENT : %.1f m", traveled))
    else
        monitor.setTextColor(colors.red)
        print("SIGNAL PERDU !")
        print("(hors de portee ou missile detruit)")
    end

    sleep(0.3)
end