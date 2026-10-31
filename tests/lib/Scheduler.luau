--[[
	Scheduler — ordonnanceur coopératif pour reproduire dans Lune les accès concurrents de
	Roblox (V0.3.1, audit de la persistance).

	Les environnements de test habituels exécutent `spawn` immédiatement et font avancer
	`wait` sans jamais rendre la main : deux tâches ne s'entrelacent jamais. Ici :
	- `spawn(fn)` met la tâche en file (comme task.spawn, elle démarre au même instant) ;
	- `wait(s)` suspend la tâche courante jusqu'à `t + s` ;
	- `clock()` renvoie un entier, comme `os.time` utilisé en jeu pour les verrous ;
	- `run(main)` déroule les tâches dans l'ordre de réveil (à égalité : ordre d'arrivée).
]]

local Scheduler = {}

function Scheduler.new(start: number?)
	local env = { t = start or 10000, logs = {}, lost = {}, health = {} }
	local queue = {}
	local seq = 0

	local function push(at: number, co: thread, args: { any }?)
		seq += 1
		table.insert(queue, { at = at, seq = seq, co = co, args = args })
	end

	function env.clock(): number
		return math.floor(env.t)
	end

	function env.wait(seconds: number)
		push(env.t + math.max(seconds, 0), coroutine.running())
		coroutine.yield()
	end

	function env.spawn(fn: (...any) -> (), ...: any)
		push(env.t, coroutine.create(fn), table.pack(...))
	end

	-- Exécute `main` et toutes les tâches qu'il lance, jusqu'à ce qu'il n'en reste plus.
	function env.run(main: () -> (), maxSteps: number?)
		env.spawn(main)
		local steps = 0
		while #queue > 0 do
			table.sort(queue, function(a, b)
				if a.at ~= b.at then
					return a.at < b.at
				end
				return a.seq < b.seq
			end)
			local item = table.remove(queue, 1)
			env.t = math.max(env.t, item.at)
			local args = item.args
			local ok, err
			if args then
				ok, err = coroutine.resume(item.co, table.unpack(args, 1, args.n))
			else
				ok, err = coroutine.resume(item.co)
			end
			if not ok then
				error(debug.traceback(item.co, tostring(err)), 0)
			end
			steps += 1
			if steps > (maxSteps or 200000) then
				error("Scheduler : trop d'étapes (boucle infinie ?)", 0)
			end
		end
	end

	return env
end

--[[
	Enveloppe un stockage simulé pour lui donner une latence (chaque appel cède la main,
	comme UpdateAsync) et des pannes « après coup » : l'écriture est appliquée, mais l'appel
	signale une erreur (délai réseau dépassé).
]]
function Scheduler.slowBackend(env: any, inner: any, latency: number?)
	local wrapper = { inner = inner, failAfterCommit = 0, failing = false }
	function wrapper.update(_self: any, key: string, transform: (any) -> any): (boolean, any)
		env.wait(latency or 0.2)
		if wrapper.failing then
			return false, "panne durable simulée"
		end
		local ok, result = inner:update(key, transform)
		if ok and wrapper.failAfterCommit > 0 then
			wrapper.failAfterCommit -= 1
			return false, "délai dépassé (écriture pourtant appliquée)"
		end
		return ok, result
	end
	function wrapper.budget(_self: any): number
		return inner:budget()
	end
	return wrapper
end

return Scheduler
