--!strict
-- Signal minimal pour la communication entre contrôleurs clients.

export type Connection = { Disconnect: (self: Connection) -> () }

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} :: { { fn: (...any) -> (), connected: boolean } } }, Signal)
end

function Signal.Connect(self: any, fn: (...any) -> ()): Connection
	local handler = { fn = fn, connected = true }
	table.insert(self._handlers, handler)
	local connection = {}
	function connection.Disconnect(_: any)
		handler.connected = false
		local index = table.find(self._handlers, handler)
		if index then
			table.remove(self._handlers, index)
		end
	end
	return connection :: any
end

function Signal.Fire(self: any, ...: any)
	for _, handler in table.clone(self._handlers) do
		if handler.connected then
			task.spawn(handler.fn, ...)
		end
	end
end

return Signal
