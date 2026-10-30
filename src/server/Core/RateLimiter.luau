--!strict
--[[
	RateLimiter — seaux à jetons par joueur et par action.
	Protège les RemoteEvents contre le spam sans pénaliser un usage normal.
]]

export type Rule = { capacity: number, refillPerSecond: number }

type Bucket = { tokens: number, at: number }

export type Limiter = {
	_rules: { [string]: Rule },
	_buckets: { [any]: { [string]: Bucket } },
	allow: (self: Limiter, key: any, action: string, now: number) -> boolean,
	forget: (self: Limiter, key: any) -> (),
}

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(rules: { [string]: Rule }): Limiter
	return (setmetatable({ _rules = rules, _buckets = {} }, RateLimiter) :: any) :: Limiter
end

function RateLimiter.allow(self: Limiter, key: any, action: string, now: number): boolean
	local rule = self._rules[action]
	if rule == nil then
		-- Action inconnue : refusée par défaut.
		return false
	end
	local perKey = self._buckets[key]
	if perKey == nil then
		perKey = {}
		self._buckets[key] = perKey
	end
	assert(perKey, "buckets")
	local bucket = perKey[action]
	if bucket == nil then
		bucket = { tokens = rule.capacity, at = now }
		perKey[action] = bucket
	end
	assert(bucket, "bucket")
	local elapsed = math.max(now - bucket.at, 0)
	bucket.tokens = math.min(rule.capacity, bucket.tokens + elapsed * rule.refillPerSecond)
	bucket.at = now
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

function RateLimiter.forget(self: Limiter, key: any)
	self._buckets[key] = nil
end

return RateLimiter
