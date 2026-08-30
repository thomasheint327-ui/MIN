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
    error("Erreur : L'API HTTP est desactivée dans la config ComputerCraft !")
end

write("Lecture de la structure de " .. REPO .. "...")

-- GitHub API exige obligatoirement un User-Agent
local headers = {
    ["User-Agent"] = "ComputerCraft-GitSync"
}

local response = http.get(API_URL, headers)

if not response then
    error("\nImpossible d'acceder a l'API GitHub (Erreur 403 / En-tete User-Agent requis).")
end

local data = textutils.unserializeJSON(response.readAll())
response.close()

if not data or not data.tree then
    error("\nFormat de reponse GitHub invalide.")
end

print(" [OK]")

-- Telechargement de l'integralite des fichiers
for _, item in ipairs(data.tree) do
    if item.type == "blob" then
        -- Ignore les dossiers internes
        if not item.path:match("^%.vscode/") and not item.path:match("^%.git") then
            local file_url = RAW_BASE .. item.path
            write("Telechargement : " .. item.path .. "...")
            
            local file_resp = http.get(file_url)
            if file_resp then
                local content = file_resp.readAll()
                file_resp.close()
                
                -- Verification et creation du dossier parent si necessaire
                local dir = fs.getDir(item.path)
                if dir and dir ~= "" and not fs.exists(dir) then
                    fs.makeDir(dir)
                end

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

print("\n[SUCCES] Tous les fichiers sont a jour !").