-- ===================================================
-- VALISE DE TIR & TELEMETRIE LIVE (POCKET)
-- Fichier : valise.lua
-- ===================================================

local modem = peripheral.find("modem", function(_, o) return o.isWireless() end)
if not modem then error("[-] Modem sans fil introuvable sur le Pocket !") end

local CANAL_TIR = 1337
local CANAL_TELEMETRIE = 1338

modem.open(CANAL_TELEMETRIE)

-- 1. SELECTION OU SAISIE DE LA CIBLE
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.yellow)
print("=== POSTE DE TIR VALISE ===")
term.setTextColor(colors.white)
print("Mode de ciblage :\n")
print("1. Coordonnees MANUELLES")
print("2. GPS Auto (Ma Position)")
term.setTextColor(colors.cyan)
write("\nChoix (1/2) : ")

local choix = read()
local cibleX, cibleY, cibleZ

if choix == "1" then
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.cyan)
    print("=== SAISIE DE CIBLE ===")
    term.setTextColor(colors.white)
    write("Cible X : ") cibleX = tonumber(read())
    write("Cible Y : ") cibleY = tonumber(read())
    write("Cible Z : ") cibleZ = tonumber(read())

    if not cibleX or not cibleY or not cibleZ then
        error("[-] Coordonnees invalides !")
    end
else
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("Recherche signal GPS...")
    cibleX, cibleY, cibleZ = gps.locate(2)
    if not cibleX then error("[-] Signal GPS introuvable.") end
end

-- 2. CONFIRMATION DU TIR
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.lime)
print("=== CIBLE VERROUILLEE ===")
print(string.format("X : %.1f", cibleX))
print(string.format("Y : %.1f", cibleY))
print(string.format("Z : %.1f", cibleZ))

term.setTextColor(colors.white)
print("\n[Appuie sur une touche]")
print("POUR MISILE EN FEU !")
os.pullEvent("key")

-- 3. ENVOI DE L'ORDRE DE TIR
modem.transmit(CANAL_TIR, CANAL_TELEMETRIE, textutils.serialize({
    action = "LANCEMENT",
    x = cibleX, y = cibleY, z = cibleZ
}))

-- 4. AFFICHAGE TELEMETRIE EN TEMPS REEL (20 Hz)
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