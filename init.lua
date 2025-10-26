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
obj.version = "0.2.1"
obj.author = "Julien Laffaye"
obj.homepage = "https://github.com/jlaffaye/HomeAssistant.spoon"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- Configuration
obj.entity_name = nil
obj.url = nil
obj.token = nil

function obj:init()
    obj.logger = hs.logger.new(obj.name, "debug")
    obj.audio_input_devices = {}
    obj.local_state = {}
end

function obj:configure(config)
    for k, v in pairs(config) do
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

    obj.caffeinate_watcher = hs.caffeinate.watcher.new(obj.on_caffeinate_event):start()
    obj.battery_watcher = hs.battery.watcher.new(obj.on_battery_event):start()
    obj.wifi_watcher = hs.wifi.watcher.new(obj.on_wifi_event):start()
    obj:startAudioInputDevicesWatcher()

    -- Send initial state
    obj.set_state(SYSTEM, "on")
    obj.set_state(SCREENS, "on")
    obj.set_state(LOCKED, "on") -- on means unlocked
    obj.set_state(SCREENSAVER, "off")

    obj.on_wifi_event()
    obj.on_battery_event()
    obj.send_audio_input_device_status()

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

    for uid, inputDevice in pairs(self.audio_input_devices) do
        inputDevice:stopWatcher()
    end

    return self
end

-- Private functions

function obj:startAudioInputDevicesWatcher()
    for i, inputDevice in pairs(hs.audiodevice.allInputDevices()) do
        -- store the device so our callback is not garbage collected
        self.audio_input_devices[inputDevice:uid()] = inputDevice

        if inputDevice:watcherIsRunning() then
            obj.logger.df("watcher is already running on input device %s", inputDevice:name())
            return
        end

        inputDevice:watcherCallback(obj.on_audio_input_device_event)
        inputDevice:watcherStart()
        obj.logger.df("started watcher on input device %s", inputDevice:name())
    end
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

function obj.on_audio_input_device_event(device_uuid, event, channel)
    if event == "gone" then
        obj.send_audio_input_device_status()
    end
end

function obj.send_audio_input_device_status()
    local in_use = "off"
    local mic_icon = "mdi:microphone-off"
    local microphone = "n/a"

    for uid, inputDevice in pairs(obj.audio_input_devices) do
        if inputDevice:inUse() then
            in_use = "on"
            mic_icon = "mdi:microphone"
            microphone = inputDevice:name()
        end
    end

    obj.set_state({
        entity = "binary_sensor.%s_microphone_in_use",
        attributes = {
            icon = mic_icon,
            microphone = microphone,
        },
    }, in_use)
end

function obj.on_caffeinate_event(event)
    local events = {
        [hs.caffeinate.watcher.screensaverDidStart] = function()
            obj.set_state(SCREENSAVER, "on")
        end,
        [hs.caffeinate.watcher.screensaverDidStop] = function()
            obj.set_state(SCREENSAVER, "off")
        end,
        [hs.caffeinate.watcher.screensDidLock] = function()
            obj.set_state(LOCKED, "off")
        end,
        [hs.caffeinate.watcher.screensDidSleep] = function()
            obj.set_state(SCREENS, "off")
        end,
        [hs.caffeinate.watcher.screensDidUnlock] = function()
            obj.set_state(LOCKED, "on")
        end,
        [hs.caffeinate.watcher.screensDidWake] = function()
            obj.set_state(SCREENS, "on")
        end,
        [hs.caffeinate.watcher.systemDidWake] = function()
            obj.set_state(SYSTEM, "on")
        end,
        [hs.caffeinate.watcher.systemWillPowerOff] = function()
            obj.set_state(SYSTEM, "off")
        end,
        [hs.caffeinate.watcher.systemWillSleep] = function()
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

function obj.set_state(conf, s)
    local data = { state = s }
    if conf.attributes then
        data["attributes"] = conf.attributes
    end

    local entity = string.format(conf.entity, obj.entity_name)
    local api = "states/" .. entity
    obj.logger.df("setting %s to %s", entity, s)

    -- Store the state locally so retries have access to the last state
    -- This is to handle the case where the set_state call A fails, then another call B succeeds, but we retry A overwriting the data set by B
    obj.local_state[api] = data

    obj.call_hass(api, data, 5)
end

function obj.call_hass(api, data, retry)
    local headers = {
        ["Authorization"] = string.format("Bearer %s", obj.token),
        ["Content-Type"] = "application/json",
    }

    local payload = hs.json.encode(data)

    local url = string.format("%s/api/%s", obj.url, api)
    hs.http.asyncPost(url, payload, headers, function(status, body, headers)
        if status <= 0 or status >= 300 then
            retry = retry - 1
            if retry < 0 then
                obj.logger.e(status, body, hs.inspect(headers))
                return
            end
            hs.timer.doAfter(1, function()
                obj.logger.f("retrying call to %s", api)
                obj.call_hass(api, obj.local_state[api], retry)
            end)
        end
    end)
end

return obj
