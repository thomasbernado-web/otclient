-- Resolves module-relative UI paths in Lua before they reach the C++ layer.
--
-- Root cause being worked around: ResourceManager::resolvePath() resolves a
-- relative path against g_lua.getCurrentSourcePath(), but when the call happens
-- inside a callback (UI button, protocol packet, scheduled event) that context
-- can be unavailable — and the isPreDrawing() branch skips it entirely — so
-- 'file' resolves to '/file.otui' (the root) and the load fails. This breaks
-- every g_ui.loadUI/displayUI/importStyle('barename') call made from a
-- callback (imbuing, outfit, console channels, VIP add/edit, shop, stash,
-- character list, ...), while the same call works from a module's init().
--
-- The fix: wrap the three entry points and, when the argument is a relative
-- path, resolve it against the *calling file's* directory (debug.getinfo),
-- but only if the target file actually exists there. In every other case the
-- argument is forwarded untouched, so behavior is identical to before.

local function resolveCallerPath(path)
    if type(path) ~= 'string' or path == '' or path:sub(1, 1) == '/' then
        return path
    end

    -- 1 = resolveCallerPath, 2 = wrapper, 3 = caller. A tail call ("return g_ui.loadUI(...)") erases the caller's
    -- frame, so keep walking up the stack until a file whose directory really holds the target.
    local level = 3
    while true do
        local info = debug.getinfo(level, 'S')
        if not info then
            return path
        end

        local src = info.source
        if src and src:sub(1, 2) == '@/' then
            local dir = src:sub(2):match('^(.*)/[^/]*$')
            if dir and dir ~= '' then
                local candidate = dir .. '/' .. path
                -- mirror g_resources.guessFilePath(candidate, 'otui')
                local candidateFile = candidate
                if candidate:sub(-5) ~= '.otui' then
                    candidateFile = candidate .. '.otui'
                end

                if g_resources.fileExists(candidateFile) then
                    return candidate
                end
            end
        end
        level = level + 1
    end
end

if not g_ui.__pathResolverInstalled then
    g_ui.__pathResolverInstalled = true

    local origLoadUI = g_ui.loadUI
    local origDisplayUI = g_ui.displayUI
    local origImportStyle = g_ui.importStyle

    g_ui.loadUI = function(path, ...)
        return origLoadUI(resolveCallerPath(path), ...)
    end

    g_ui.displayUI = function(path, ...)
        return origDisplayUI(resolveCallerPath(path), ...)
    end

    g_ui.importStyle = function(path, ...)
        return origImportStyle(resolveCallerPath(path), ...)
    end
end
