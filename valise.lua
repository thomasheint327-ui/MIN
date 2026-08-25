-- ===================================================
-- VALISE DE TIR ET STATION DE TELEMETRIE POCKET
-- Fichier : valise.lua
-- ===================================================

local modem = peripheral.find("modem", function(_, o) return o.isWireless() end)
if not modem then error("[-] Modem sans fil introuvable sur le Pocket !") end

local CANAL_TIR = 1337
local CANAL_TELEMETRIE = 1338

modem.open(CANAL_TELEMETRIE)

-- 1. FIXATION GPS DE LA CIBLE
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.yellow)
print("=== VALISE DE TIR ===")
print("Recherche signal GPS...")

local cibleX, cibleY, cibleZ = gps.locate(2)
if not cibleX then error("[-] Signal GPS introuvable. Deplacement requis.") end

term.setTextColor(colors.green)
print(string.format("Cible : X:%.1f Y:%.1f Z:%.1f", cibleX, cibleY, cibleZ))
term.setTextColor(colors.white)
print("\n[Appuie sur une touche]")
print("POUR ORDONNER LE TIR")
os.pullEvent("key")

-- 2. ENVOI DE L'ORDRE DE TIR
modem.transmit(CANAL_TIR, CANAL_TELEMETRIE, textutils.serialize({
    action = "LANCEMENT",
    x = cibleX, y = cibleY, z = cibleZ
}))

-- 3. AFFICHAGE TELEMETRIE EN TEMPS REEL (20 Hz)
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.red)
print("=== TELEMETRIE MISSILE LIVE ===")

while true do
    local _, _, chan, _, message = os.pullEvent("modem_message")
    if chan == CANAL_TELEMETRIE then
        local data = textutils.unserialize(message)
        if data then
            term.setCursorPos(1, 3)
            term.setTextColor(colors.yellow)
            term.clearLine()
            print(string.format("Pos : %.1f, %.1f, %.1f", data.x or 0, data.y or 0, data.z or 0))

            term.setCursorPos(1, 4)
            term.setTextColor(colors.cyan)
            term.clearLine()
            print(string.format("Distance : %.1f m", data.dist or 0))

            term.setCursorPos(1, 5)
            term.setTextColor(colors.lime)
            term.clearLine()
            print(string.format("Vitesse  : %.1f m/s", data.vit or 0))

            term.setCursorPos(1, 6)
            term.setTextColor(colors.orange)
            term.clearLine()
            print(string.format("Altitude : %.1f m", data.alt or 0))

            term.setCursorPos(1, 7)
            term.setTextColor(colors.magenta)
            term.clearLine()
            print(string.format("Gimbal P/Y: %.0f / %.0f", data.pitch or 0, data.yaw or 0))

            term.setCursorPos(1, 9)
            term.setTextColor(colors.white)
            term.clearLine()
            print("Statut : " .. (data.status or "EN VOL"))

            if data.status == "IMPACT" or data.status == "ARRET" then
                term.setCursorPos(1, 11)
                term.setTextColor(colors.red)
                print(">>> FIN DE TRANSMISSION <<<")
                break
            end
        end
    end
end