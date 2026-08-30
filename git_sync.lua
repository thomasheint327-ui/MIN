local USERNAME = "thomasheint327-ui"
local REPO     = "MIN"
local BRANCH   = "main"

local API_URL  = string.format("https://api.github.com/repos/%s/%s/git/trees/%s?recursive=1", USERNAME, REPO, BRANCH)
local RAW_BASE = string.format("https://raw.githubusercontent.com/%s/%s/%s/", USERNAME, REPO, BRANCH)

term.clear()
term.setCursorPos(1, 1)
print("========================================")
print("   CLONAGE D'ENSEMBLE DU DEPOT GITHUB   ")
print("========================================")

if not http then
    error("Erreur : L'API HTTP est désactivée dans la config ComputerCraft !")
end

write("Lecture de la structure de " .. REPO .. "...")
local response = http.get(API_URL)

if not response then
    error("\nImpossible d'accéder à l'API GitHub. Vérifie la connexion HTTP.")
end

local data = textutils.unserializeJSON(response.readAll())
response.close()

if not data or not data.tree then
    error("\nFormat de réponse GitHub invalide.")
end

print(" [OK]")

-- Téléchargement de l'intégralité des fichiers
for _, item in ipairs(data.tree) do
    if item.type == "blob" then
        -- Ignore les dossiers internes comme .vscode
        if not item.path:match("^%.vscode/") then
            local file_url = RAW_BASE .. item.path
            write("Téléchargement : " .. item.path .. "...")
            
            local file_resp = http.get(file_url)
            if file_resp then
                local content = file_resp.readAll()
                file_resp.close()
                
                local f = fs.open(item.path, "w")
                if f then
                    f.write(content)
                    f.close()
                    print(" [OK]")
                end
            else
                print(" [ECHEC]")
            end
        end
    end
end

print("\n[SUCCÈS] Tous les fichiers sont à jour !")