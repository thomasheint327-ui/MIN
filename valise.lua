-- ===================================================
-- VALISE DE TIR GUI - RUN AUTO & MAINTENANCE (20 Hz)
-- Fichier : valise.lua
-- ===================================================

local modem = peripheral.find("modem", function(_, o) return o.isWireless() end)
if not modem then error("[-] Modem sans fil introuvable !") end

local CANAL_TIR = 1337
local CANAL_TELEMETRIE = 1338
modem.open(CANAL_TELEMETRIE)

local width, height = term.getSize()
local cibleX, cibleY, cibleZ = 0, 0, 0

-- --- MENU SELECTION DU MODE DE DEMARRAGE ---
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.yellow)
print("=== BOOT VALISE DE TIR ===")
term.setTextColor(colors.white)
print("1. Mode RUN (GUI Auto dans 3s)")
print("2. Mode MAINTENANCE (Console)")

local timerId = os.startTimer(3)
local modeMaintenance = false

while true do
    local event, p1 = os.pullEvent()
    if event == "timer" and p1 == timerId then
        break
    elseif event == "char" then
        if p1 == "2" then modeMaintenance = true end
        break
    end
end

if modeMaintenance then
    term.setTextColor(colors.cyan)
    print("\n[!] Mode MAINTENANCE actif. Console ouverte.")
    return
end

-- --- FONCTIONS DE DESSIN ---
local function dessinerEnTete(titre)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.setCursorPos(1, 1)
    term.clearLine()
    local posPad = math.floor((width - #titre) / 2)
    term.setCursorPos(math.max(1, posPad + 1), 1)
    write(titre)
    term.setBackgroundColor(colors.black)
end

local function dessinerBouton(x, y, w, text, bgCol, fgCol)
    term.setBackgroundColor(bgCol)
    term.setTextColor(fgCol)
    term.setCursorPos(x, y)
    write(string.rep(" ", w))
    local textPos = x + math.floor((w - #text) / 2)
    term.setCursorPos(textPos, y)
    write(text)
    term.setBackgroundColor(colors.black)
end

-- --- ECRAN 1 : CIBLAGE ---
local function ecranCiblage()
    while true do
        term.setBackgroundColor(colors.black)
        term.clear()
        dessinerEnTete("VALISE DE TIR GUI")

        term.setTextColor(colors.yellow)
        term.setCursorPos(2, 3) write("Cible verrouillee :")
        
        term.setTextColor(colors.white)
        term.setCursorPos(3, 4) write(string.format("X : %.1f", cibleX))
        term.setCursorPos(3, 5) write(string.format("Y : %.1f", cibleY))
        term.setCursorPos(3, 6) write(string.format("Z : %.1f", cibleZ))

        dessinerBouton(2, 8,  22, "[ 1. COORDONNEES ]", colors.blue, colors.white)
        dessinerBouton(2, 10, 22, "[ 2. GPS AUTO    ]", colors.purple, colors.white)
        dessinerBouton(2, 12, 22, ">>> MISSILE FEU <<<", colors.red, colors.white)
        dessinerBouton(2, 14, 22, "[ MAINTENANCE ]", colors.gray, colors.white)

        local event, button, x, y = os.pullEvent()
        
        if event == "mouse_click" or event == "monitor_touch" then
            if y == 8 then
                term.setBackgroundColor(colors.black)
                term.clear()
                dessinerEnTete("SAISIE MANUELLE")
                term.setTextColor(colors.cyan)
                term.setCursorPos(2, 4) write("Cible X : ") cibleX = tonumber(read()) or cibleX
                term.setCursorPos(2, 6) write("Cible Y : ") cibleY = tonumber(read()) or cibleY
                term.setCursorPos(2, 8) write("Cible Z : ") cibleZ = tonumber(read()) or cibleZ

            elseif y == 10 then
                term.setCursorPos(2, 11)
                term.setTextColor(colors.orange) write("Signal GPS...")
                local gx, gy, gz = gps.locate(2)
                if gx then cibleX, cibleY, cibleZ = gx, gy, gz end

            elseif y == 12 then
                if cibleX ~= 0 or cibleY ~= 0 or cibleZ ~= 0 then
                    modem.transmit(CANAL_TIR, CANAL_TELEMETRIE, textutils.serialize({
                        action = "LANCEMENT", x = cibleX, y = cibleY, z = cibleZ
                    }))
                    return "FEU"
                end

            elseif y == 14 then
                return "MAINTENANCE"
            end
        end
    end
end

-- --- ECRAN 2 : TELEMETRIE ---
local function ecranTelemetrie()
    term.setBackgroundColor(colors.black)
    term.clear()
    dessinerEnTete("TELEMETRIE 20Hz LIVE")
    dessinerBouton(2, height - 1, width - 2, "[ RETOUR AU MENU ]", colors.red, colors.white)

    while true do
        local event, p1, p2, p3, p4 = os.pullEvent()

        if event == "mouse_click" or event == "monitor_touch" then
            if p3 == height - 1 then break end
        end

        if event == "modem_message" and p2 == CANAL_TELEMETRIE then
            local data = textutils.unserialize(p4)
            if data then
                term.setBackgroundColor(colors.black)
                term.setCursorPos(2, 3) term.setTextColor(colors.yellow) term.clearLine()
                write(string.format("POS : %.1f, %.1f, %.1f", data.x or 0, data.y or 0, data.z or 0))

                term.setCursorPos(2, 4) term.setTextColor(colors.cyan) term.clearLine()
                write(string.format("DIST CIBLE : %.1f m", data.dist or 0))

                term.setCursorPos(2, 5) term.setTextColor(colors.lime) term.clearLine()
                write(string.format("VITESSE    : %.1f m/s", data.vit or 0))

                term.setCursorPos(2, 6) term.setTextColor(colors.orange) term.clearLine()
                write(string.format("ALTITUDE   : %.1f m", data.alt or 0))

                term.setCursorPos(2, 7) term.setTextColor(colors.magenta) term.clearLine()
                write(string.format("GIMBAL P/Y : %.0f / %.0f", data.pitch or 0, data.yaw or 0))

                term.setCursorPos(2, 9) term.clearLine()
                if data.status == "IMPACT" then
                    term.setBackgroundColor(colors.lime) term.setTextColor(colors.black)
                    write(" === IMPACT CONFIRME ! === ")
                    dessinerBouton(2, height - 1, width - 2, "[ NOUVEAU TIR ]", colors.blue, colors.white)
                elseif data.status == "ARRET" then
                    term.setBackgroundColor(colors.red) term.setTextColor(colors.white)
                    write(" === TEMPS ECOULE === ")
                    dessinerBouton(2, height - 1, width - 2, "[ RETOUR MENU ]", colors.gray, colors.white)
                else
                    term.setBackgroundColor(colors.black) term.setTextColor(colors.white)
                    write("STATUT : " .. (data.status or "EN VOL"))
                end
            end
        end
    end
end

-- ===================================================
-- BOUCLE INFINIE APPLICATION (MODE RUN)
-- ===================================================
while true do
    local action = ecranCiblage()
    if action == "FEU" then
        ecranTelemetrie()
    elseif action == "MAINTENANCE" then
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.clear()
        term.setCursorPos(1, 1)
        print("Fermeture de l'interface valise.")
        return
    end
end