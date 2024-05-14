--- === HomeAssistant ===
---
local obj = { __gc = true }
--obj.__index = obj
setmetatable(obj, obj)
obj.__gc = function(t)
    t:stop()
end

-- Metadata
obj.name = "HomeAssistant"
obj.version = "0.1"
obj.author = "Julien Laffaye"
obj.homepage = "https://github.com/jlaffaye/HomeAssistant.spoon"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- Configuration
obj.entity_name = nil
obj.url = nil
obj.token = nil

function obj:init()
    obj.logger = hs.logger.new(obj.name, "debug")
    obj.microphone_device_uid = hs.audiodevice.defaultInputDevice():uid()
end

function obj:configure(config)
    for k,v in pairs(config) do
        self[k] = v
     end
    return self
end

function obj:validate_config()
    if not obj.entity_name then
        obj.logger.e("you must set entity_name before start")
        error("entity_name expected", 2)
    end

    if not string.match(obj.entity_name, "^[a-z0-9]+[_a-z0-9]*$") then
        obj.logger.ef("entity_name must only contain alnum in snake_case, got %s", obj.entity_name)
        error("entity_name must only contain alnum in snake_case", 2)
    end

    if not obj.url then
        obj.logger.e("you must set url before start")
        error("url expected", 2)
    end

    if not obj.token then
        obj.logger.e("you must set token before start")
        error("token expected", 2)
    end

    if not hs.audiodevice.findInputByUID(obj.microphone_device_uid) then
        obj.logger.ef("can not find input device with microphone_device_uid=%s", obj.microphone_device_uid)
        error("bad microphone_device_uid", 2)
    end
end

--- HomeAssistant:start()
--- Method
--- Starts HomeAssistant
---
--- Parameters:
---  * None
---
--- Returns:
---  * The HomeAssistant object
function obj:start()
    obj:validate_config()

    -- Send initial state
    obj.set_state(SYSTEM, "on")
    obj.set_state(SCREENS, "on")
    obj.set_state(LOCKED, "on") -- on means unlocked
    obj.set_state(SCREENSAVER, "off")

    obj.on_wifi_event()
    obj.on_battery_event()
    obj.send_audio_device_status(obj.microphone_device_uid)

    obj.caffeinate_watcher =  hs.caffeinate.watcher.new(obj.on_caffeinate_event):start()
    obj.battery_watcher = hs.battery.watcher.new(obj.on_battery_event):start()
    obj.wifi_watcher = hs.wifi.watcher.new(obj.on_wifi_event):start()
    obj:startAudioDeviceWatcher()

    return self
end

--- HomeAssistant:stop()
--- Method
--- Stops HomeAssistant
---
--- Parameters:
---  * None
---
--- Returns:
---  * The HomeAssistant object
function obj:stop()
    if self.caffeinate_watcher then
        self.caffeinate_watcher:stop()
        self.caffeinate_watcher = nil
    end

    if self.battery_watcher then
        self.battery_watcher:stop()
        self.battery_watcher = nil
    end

    if self.wifi_watcher then
        self.wifi_watcher:stop()
        self.wifi_watcher = nil
    end

    return self
end

-- Private functions

function obj:startAudioDeviceWatcher()
    local inputDevice = hs.audiodevice.findInputByUID(obj.microphone_device_uid)

    if inputDevice:watcherIsRunning() then
        obj.logger.df("watcher is already running on input device %s", inputDevice:name())
        return
    end

    inputDevice:watcherCallback(obj.on_audio_device_event)
    inputDevice:watcherStart()
    obj.logger.df("started watcher on input device %s", inputDevice:name())
end

SYSTEM = {
    entity = "binary_sensor.%s_system",
    attributes = {
        device_class = "running",
    },
}
SCREENSAVER = {
    entity = "binary_sensor.%s_screensaver",
    attributes = {
        device_class = "running",
    },
}
SCREENS = {
    entity = "binary_sensor.%s_screens",
}
LOCKED = {
    entity = "binary_sensor.%s_locked",
    attributes = {
        device_class = "lock",
    },
}

function obj.on_audio_device_event(device_uuid, event, channel)
    if event == "gone" then
        obj.send_audio_device_status(device_uuid)
    end
end

function obj.send_audio_device_status(device_uuid)
    local input_device = hs.audiodevice.findInputByUID(device_uuid)
    local in_use = "off"
    local mic_icon = "mdi:microphone-off"
    if input_device:inUse() then
        in_use = "on"
        mic_icon = "mdi:microphone"
    end

    obj.set_state({
        entity = "binary_sensor.%s_microphone_in_use",
        attributes = {
            icon = mic_icon,
            microphone = input_device:name(),
        },
    }, in_use)
end

function obj.on_caffeinate_event(event)
    local events = {
        [hs.caffeinate.watcher.screensaverDidStart] = function ()
            obj.set_state(SCREENSAVER, "on")
        end,
        [hs.caffeinate.watcher.screensaverDidStop]= function ()
            obj.set_state(SCREENSAVER, "off")
        end,
        [hs.caffeinate.watcher.screensDidLock] = function ()
            obj.set_state(LOCKED, "off")
        end,
        [hs.caffeinate.watcher.screensDidSleep] = function ()
            obj.set_state(SCREENS, "off")
        end,
        [hs.caffeinate.watcher.screensDidUnlock] = function ()
            obj.set_state(LOCKED, "on")
        end,
        [hs.caffeinate.watcher.screensDidWake] = function ()
            obj.set_state(SCREENS, "on")
        end,
        [hs.caffeinate.watcher.systemDidWake] = function ()
            obj.set_state(SYSTEM, "on")
        end,
        [hs.caffeinate.watcher.systemWillPowerOff] = function ()
            obj.set_state(SYSTEM, "off")
        end,
        [hs.caffeinate.watcher.systemWillSleep] = function ()
            obj.set_state(SYSTEM, "off")
        end,
    }

    local func = events[event]
    if func then
        func()
    end
end

function obj.on_battery_event()
    local time_full_charge = hs.battery.timeToFullCharge()
    obj.set_state({
        entity = "sensor.%s_battery_time_full_charge",
        attributes = {
            device_class = "duration",
            unit_of_measurement = "min",
        },
    }, time_full_charge)

    local time_remaining = hs.battery.timeRemaining()
    obj.set_state({
        entity = "sensor.%s_battery_time_remaining",
        attributes = {
            device_class = "duration",
            unit_of_measurement = "min",
        },
    }, time_remaining)

    local plugged = "off"
    if hs.battery.powerSource() == "AC Power" then
        plugged = "on"
    end
    obj.set_state({
        entity = "binary_sensor.%s_plugged",
        attributes = {
            device_class = "plug",
        },
    }, plugged)

    obj.set_state({
        entity = "sensor.%s_battery",
        attributes = {
            device_class = "battery",
            unit_of_measurement = "%",
        },
    }, hs.battery.percentage())

    local battery_charging = "off"
    if hs.battery.isCharging() then
        battery_charging = "on"
    end
    obj.set_state({
        entity = "binary_sensor.%s_battery_charging",
        attributes = {
            device_class = "battery_charging",
        },
    }, battery_charging)
end

function obj.on_wifi_event()
    local ssid = hs.wifi.currentNetwork()
    local wifi_icon = "mdi:wifi"
    if not ssid then
        wifi_icon = "mdi:wifi-off"
    end
    obj.set_state({
        entity = "sensor.%s_ssid",
        attributes = {
            icon = wifi_icon,
        },
    }, ssid)
end

------------------------------
-- Home Assistant REST API ---
------------------------------

function obj.http_callback(status, body, headers)
    if status >= 300 then
        obj.logger.e(status, body, hs.inspect(headers))
    end
end

function obj.set_state(conf, s)
    local data = { state = s}
    if conf.attributes then
        data["attributes"] = conf.attributes
    end

    local entity = string.format(conf.entity, obj.entity_name)

    obj.logger.df("setting %s to %s", entity, s)

    obj.call_hass("states/" .. entity, data)
end

function obj.call_hass(api, data)
    local headers = {
        ["Authorization"]= string.format("Bearer %s", obj.token),
        ["Content-Type"]= "application/json",
    }

    local payload = hs.json.encode(data)

    local url = string.format("%s/api/%s", obj.url, api)
    hs.http.asyncPost(url, payload, headers, obj.http_callback)
end

return obj
