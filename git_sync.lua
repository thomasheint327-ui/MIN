-- ============================================================================
-- GIT_SYNC.LUA - SYNCHRONISATION GITHUB (AVEC ANTI-CACHE)
-- ============================================================================

local USER = "thomasheint327-ui"
local REPO = "MIN"
local BRANCH = "main"

local API_URL = string.format("https://api.github.com/repos/%s/%s/git/trees/%s?recursive=1", USER, REPO, BRANCH)
local RAW_BASE = string.format("https://raw.githubusercontent.com/%s/%s/%s/", USER, REPO, BRANCH)

print("Connexion a GitHub...")

local response = http.get(API_URL)
if not response then
    print("[ERREUR] Impossible de contacter l'API GitHub.")
    return
end

local body = response.readAll()
response.close()

local data = textutils.unserialiseJSON(body)
if not data or not data.tree then
    print("[ERREUR] Reponse GitHub invalide.")
    return
end

print("Mise a jour des fichiers...")

for _, item in ipairs(data.tree) do
    if item.type == "blob" then
        -- Bypass du cache raw.githubusercontent via os.epoch
        local file_url = RAW_BASE .. item.path .. "?cb=" .. os.epoch("utc")
        local res = http.get(file_url)
        
        if res then
            local content = res.readAll()
            res.close()

            local file = fs.open(item.path, "w")
            if file then
                file.write(content)
                file.close()
                print(" [OK] " .. item.path)
            else
                print(" [ERREUR] Ecriture impossible : " .. item.path)
            end
        else
            print(" [ERREUR] Telechargement echoue : " .. item.path)
        end
    end
end

print("\n[SUCCES] Tous les fichiers sont a jour !")