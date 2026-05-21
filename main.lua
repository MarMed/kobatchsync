local Device = require("device")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local md5 = require("ffi/sha2").md5
local util = require("util")
local _ = require("gettext")

local DocSettings = require("docsettings")
local ReadHistory = require("readhistory")
local Math = require("optmath")

local BatchSync = WidgetContainer:extend{
    name = "kobatchsync",
    is_doc_only = false,
    title = _("Batch Progress Sync"),
}

function BatchSync:init()
    self.ui.menu:registerToMainMenu(self)
    self.KOSyncClient = dofile(self.path .. "/KOSyncClient.lua")
end

function BatchSync:onDispatcherRegisterActions()
    Dispatcher:registerAction("kobatchsync_push_all", { category="none", event="BatchSyncPush", title=_("Batch push progress for all books"), reader=true,})
    Dispatcher:registerAction("kobatchsync_pull_all", { category="none", event="BatchSyncPull", title=_("Batch pull progress for all books"), reader=true, separator=true,})
end

function BatchSync:onReaderReady()
    self:onDispatcherRegisterActions()
end

function BatchSync:addToMainMenu(menu_items)
    menu_items.batch_sync = {
        text = _("Batch progress sync"),
        sub_item_table = {
            {
                text = _("Batch push progress from this device (all books)"),
                enabled_func = function()
                    local s = G_reader_settings:readSetting("kosync")
                    return s and s.userkey ~= nil
                end,
                callback = function()
                    self:batchUpdateProgress(true, true)
                end,
            },
            {
                text = _("Batch pull progress from other devices (all books)"),
                enabled_func = function()
                    local s = G_reader_settings:readSetting("kosync")
                    return s and s.userkey ~= nil
                end,
                callback = function()
                    self:batchGetProgress(true, true)
                end,
                separator = true,
            },
        }
    }
end



function BatchSync:batchUpdateProgress(ensure_networking, interactive)
    local kosync_settings = G_reader_settings:readSetting("kosync")
    if not kosync_settings or not kosync_settings.username or not kosync_settings.userkey then
        if interactive then
            UIManager:show(InfoMessage:new{
                text = _("Please register or login in Progress Sync before using batch sync."),
                timeout = 3,
            })
        end
        return
    end

    if ensure_networking and NetworkMgr:willRerunWhenOnline(function() self:batchUpdateProgress(ensure_networking, interactive) end) then
        return
    end

    ReadHistory:reload(true)
    if #ReadHistory.hist == 0 then
        if interactive then
            UIManager:show(InfoMessage:new{ text = _("Reading history is empty."), timeout = 3 })
        end
        return
    end

    local client = self.KOSyncClient:new{
        custom_url = kosync_settings.custom_server,
        service_spec = self.path .. "/api.json"
    }

    local chosen_device_name = kosync_settings.kosync_hostname or Device.model
    local device_id = G_reader_settings:readSetting("device_id")
    local checksum_method = kosync_settings.checksum_method or 0 

    local success_count, fail_count, skip_count = 0, 0, 0
    local total = #ReadHistory.hist
    local current_idx = 1
    
    local is_aborted = false
    local is_finished = false

    local ProgressbarDialog = require("ui/widget/progressbardialog")
    local Font = require("ui/font")
    local notification = ProgressbarDialog:new{
        title = _("Batch Push Progress"),
        subtitle = _("Syncing... please wait"),
        progress_max = total,
        refresh_time_seconds = 0.5,
        dismissable = true,
        dismiss_callback = function()
            if not is_finished then
                is_aborted = true
            end
        end,
    }
    UIManager:show(notification)

    local function updateSubtitle(text)
        local vertical_group = notification[1] and notification[1][1]
        if vertical_group then
            for i = 1, #vertical_group do
                local widget = vertical_group[i]
                if widget.setText and widget.face == Font:getFace("smallffont") then
                    widget:setText(text)
                    vertical_group:resetLayout()
                    notification[1].dimen = nil
                    UIManager:setDirty(notification, function() return "ui", notification[1].dimen end)
                    UIManager:forceRePaint()
                    return
                end
            end
        end
    end

    updateSubtitle(_("Success: 0 | Skipped: 0 | Failed: 0"))

    local function processNext()
        if is_aborted then
            if interactive then
                UIManager:show(InfoMessage:new{
                    text = _("Batch push cancelled by user."),
                    timeout = 3,
                })
            end
            if Device:hasWifiManager() then
                NetworkMgr:afterWifiAction()
            end
            return
        end

        while true do
            if current_idx > total then
                is_finished = true
                UIManager:close(notification)
                if interactive then
                    UIManager:show(InfoMessage:new{
                        text = _("Batch push complete\nSuccess: ") .. success_count .. _("\nSkipped: ") .. skip_count .. _("\nFailed: ") .. fail_count,
                        timeout = 3,
                    })
                end
                if Device:hasWifiManager() then
                    NetworkMgr:afterWifiAction()
                end
                return
            end

            local hist_item = ReadHistory.hist[current_idx]
            current_idx = current_idx + 1

            local is_skipped = false
            local book_file, doc_settings, percent_finished, progress, doc_digest

            if not hist_item.select_enabled then
                is_skipped = true
            else
                book_file = hist_item.file
                doc_settings = DocSettings:open(book_file)
                if not doc_settings or not doc_settings.data then
                    is_skipped = true
                else
                    percent_finished = doc_settings:readSetting("percent_finished")
                    local last_page = doc_settings:readSetting("last_page")
                    local last_xpointer = doc_settings:readSetting("last_xpointer")
                    progress = last_page or last_xpointer
                    if not progress then
                        progress = percent_finished
                    end

                    if not progress then
                        is_skipped = true
                    else
                        if checksum_method == 1 then
                            local file_path, file_name = util.splitFilePathName(book_file)
                            if file_name then doc_digest = md5(file_name) end
                        else
                            doc_digest = doc_settings:readSetting("partial_md5_checksum")
                            if not doc_digest then
                                doc_digest = util.partialMD5(book_file)
                                if doc_digest then
                                    doc_settings.data.partial_md5_checksum = doc_digest
                                    doc_settings:flush()
                                end
                            end
                        end

                        if not doc_digest then
                            is_skipped = true
                        end
                    end
                end
            end

            if is_skipped then
                skip_count = skip_count + 1
                -- continue loop synchronously
            else
                -- Update UI exactly once before making the network request
                notification:reportProgress(current_idx - 1)
                updateSubtitle(_("Success: ") .. success_count .. _(" | Skipped: ") .. skip_count .. _(" | Failed: ") .. fail_count)

                local ok, err = pcall(client.update_progress,
                    client,
                    kosync_settings.username,
                    kosync_settings.userkey,
                    doc_digest,
                    tostring(progress),
                    percent_finished or 0,
                    chosen_device_name,
                    device_id,
                    function(ok, body)
                        if ok then
                            success_count = success_count + 1
                            logger.dbg("BatchSync: [Push] progress to", (percent_finished or 0) * 100, "% =>", progress, "for", book_file)
                        else
                            fail_count = fail_count + 1
                            logger.warn("BatchSync Push fail for", book_file, body)
                        end
                        
                        UIManager:scheduleIn(0.2, processNext)
                    end)
                    
                if not ok then
                    logger.warn("BatchSync push call failed:", err)
                    fail_count = fail_count + 1
                    UIManager:scheduleIn(0.2, processNext)
                end
                return -- Stop the sync loop to wait for async callback
            end
        end
    end

    processNext()
end

function BatchSync:batchGetProgress(ensure_networking, interactive)
    local kosync_settings = G_reader_settings:readSetting("kosync")
    if not kosync_settings or not kosync_settings.username or not kosync_settings.userkey then
        if interactive then
            UIManager:show(InfoMessage:new{
                text = _("Please register or login in Progress Sync before using batch sync."),
                timeout = 3,
            })
        end
        return
    end

    if ensure_networking and NetworkMgr:willRerunWhenOnline(function() self:batchGetProgress(ensure_networking, interactive) end) then
        return
    end

    local ProgressbarDialog = require("ui/widget/progressbardialog")
    local DocumentRegistry = require("document/documentregistry")
    local Font = require("ui/font")
    local lfs = require("libs/libkoreader-lfs")

    ReadHistory:reload(true)
    
    local target_files = {}
    local seen_files = {}

    for _, v in ipairs(ReadHistory.hist) do
        if v.select_enabled then
            table.insert(target_files, v.file)
            seen_files[v.file] = true
        end
    end

    local home_dir = G_reader_settings:readSetting("home_dir") or "/mnt/sdcard"
    if lfs.attributes(home_dir, "mode") == "directory" then
        local ok, iter, dir_obj = pcall(lfs.dir, home_dir)
        if ok and iter then
            for file in iter, dir_obj do
                if file ~= "." and file ~= ".." then
                    local full_path = home_dir .. "/" .. file
                    if not seen_files[full_path] and lfs.attributes(full_path, "mode") == "file" then
                        if DocumentRegistry:hasProvider(full_path) then
                            table.insert(target_files, full_path)
                            seen_files[full_path] = true
                        end
                    end
                end
            end
        end
    end

    if #target_files == 0 then
        if interactive then
            UIManager:show(InfoMessage:new{ text = _("No supported reading items found in history or home directory."), timeout = 3 })
        end
        return
    end

    local client = self.KOSyncClient:new{
        custom_url = kosync_settings.custom_server,
        service_spec = self.path .. "/api.json"
    }

    local device_id = G_reader_settings:readSetting("device_id")
    local checksum_method = kosync_settings.checksum_method or 0 

    local success_count, fail_count, skip_count = 0, 0, 0
    local total = #target_files
    local current_idx = 1
    
    local is_aborted = false
    local is_finished = false

    local notification = ProgressbarDialog:new{
        title = _("Batch Pull Progress"),
        subtitle = _("Syncing... please wait"),
        progress_max = total,
        refresh_time_seconds = 0.5,
        dismissable = true,
        dismiss_callback = function()
            if not is_finished then
                is_aborted = true
            end
        end,
    }
    UIManager:show(notification)

    local function updateSubtitle(text)
        local vertical_group = notification[1] and notification[1][1]
        if vertical_group then
            for i = 1, #vertical_group do
                local widget = vertical_group[i]
                if widget.setText and widget.face == Font:getFace("smallffont") then
                    widget:setText(text)
                    vertical_group:resetLayout()
                    notification[1].dimen = nil
                    UIManager:setDirty(notification, function() return "ui", notification[1].dimen end)
                    UIManager:forceRePaint()
                    return
                end
            end
        end
    end

    updateSubtitle(_("Updated: 0 | Skipped: 0 | Failed: 0"))

    local function processNext()
        if is_aborted then
            if interactive then
                UIManager:show(InfoMessage:new{
                    text = _("Batch pull cancelled by user."),
                    timeout = 3,
                })
            end
            if Device:hasWifiManager() then
                NetworkMgr:afterWifiAction()
            end
            return
        end

        while true do
            if current_idx > total then
                is_finished = true
                UIManager:close(notification)
                if interactive then
                    UIManager:show(InfoMessage:new{
                        text = _("Batch pull complete\nUpdated: ") .. success_count .. _("\nSkipped: ") .. skip_count .. _("\nFailed: ") .. fail_count,
                        timeout = 3,
                    })
                end
                if Device:hasWifiManager() then
                    NetworkMgr:afterWifiAction()
                end
                return
            end

            local book_file = target_files[current_idx]
            current_idx = current_idx + 1

            local doc_settings = DocSettings:open(book_file)
            local percent_finished = doc_settings and doc_settings:readSetting("percent_finished")
            local last_page = doc_settings and doc_settings:readSetting("last_page")
            local last_xpointer = doc_settings and doc_settings:readSetting("last_xpointer")
            local progress = last_page or last_xpointer
            if not progress then
                progress = percent_finished
            end

            local doc_digest
            if checksum_method == 1 then
                local file_path, file_name = util.splitFilePathName(book_file)
                if file_name then doc_digest = md5(file_name) end
            else
                if doc_settings and doc_settings.data then
                    doc_digest = doc_settings:readSetting("partial_md5_checksum")
                end
                if not doc_digest then
                    doc_digest = util.partialMD5(book_file)
                end
            end

            if not doc_digest then
                skip_count = skip_count + 1
                -- continue loop synchronously
            else
                -- Update UI exactly once before making the network request
                notification:reportProgress(current_idx - 1)
                updateSubtitle(_("Updated: ") .. success_count .. _(" | Skipped: ") .. skip_count .. _(" | Failed: ") .. fail_count)

                -- We found a valid book digest, perform the network get_progress call!
                local ok, err = pcall(client.get_progress,
                    client,
                    kosync_settings.username,
                    kosync_settings.userkey,
                    doc_digest,
                    function(ok, body, status)
                        if status == 404 then
                            skip_count = skip_count + 1
                            logger.dbg("BatchSync: [Pull] No progress on server for", book_file)
                        elseif not ok or not body or not body.percentage then
                            fail_count = fail_count + 1
                            logger.warn("BatchSync Pull fail/empty for", book_file, body)
                        elseif body.device == Device.model and body.device_id == device_id then
                            skip_count = skip_count + 1
                            logger.dbg("BatchSync: [Pull] Latest progress is from this device for", book_file)
                        else
                            body.percentage = Math.roundPercent(body.percentage)
                            if (percent_finished or 0) == body.percentage or body.progress == tostring(progress) then
                                skip_count = skip_count + 1
                            else
                                -- update the doc_settings silently
                                local fresh_settings = DocSettings:open(book_file)
                                if fresh_settings and fresh_settings.data then
                                    if checksum_method == 0 then
                                        fresh_settings.data.partial_md5_checksum = doc_digest
                                    end
                                    fresh_settings.data.percent_finished = body.percentage
                                    local num_progress = tonumber(body.progress)
                                    if num_progress then
                                        fresh_settings.data.last_page = num_progress
                                    else
                                        fresh_settings.data.last_xpointer = body.progress
                                    end
                                    fresh_settings:flush()
                                end
                                
                                -- If this is the currently opened document, we also emit an event to navigate
                                if self.ui.document and self.ui.document.file == book_file then
                                    if self.ui.doc_settings then
                                        if checksum_method == 0 then
                                            self.ui.doc_settings.data.partial_md5_checksum = doc_digest
                                        end
                                        self.ui.doc_settings.data.percent_finished = body.percentage
                                        local num_progress = tonumber(body.progress)
                                        if num_progress then
                                            self.ui.doc_settings.data.last_page = num_progress
                                        else
                                            self.ui.doc_settings.data.last_xpointer = body.progress
                                        end
                                    end
                                    local num_progress = tonumber(body.progress)
                                    if num_progress then
                                        self.ui:handleEvent(Event:new("GotoPage", num_progress))
                                    else
                                        self.ui:handleEvent(Event:new("GotoXPointer", body.progress))
                                    end
                                end
                                
                                success_count = success_count + 1
                                logger.dbg("BatchSync: [Pull] Update", book_file, "to", body.percentage, body.progress)
                            end
                        end
                        
                        UIManager:scheduleIn(0.2, processNext)
                    end)
                    
                if not ok then
                    logger.warn("BatchSync pull call failed:", err)
                    fail_count = fail_count + 1
                    UIManager:scheduleIn(0.2, processNext)
                end
                return -- Stop the sync loop to wait for async callback
            end
        end
    end

    processNext()
end

function BatchSync:onBatchSyncPush()
    self:batchUpdateProgress(true, true)
end

function BatchSync:onBatchSyncPull()
    self:batchGetProgress(true, true)
end

return BatchSync
