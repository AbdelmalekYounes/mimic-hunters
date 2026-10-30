--!strict
--[[
	TutorialFlow — étapes du tutoriel de première capture.

	Scan → Inspect → Capture → Done
	Les étapes peuvent être sautées (un joueur qui examine directement l'objet
	passe à Capture). Un échec ramène à Inspect, sans autre pénalité.
]]

export type Step = "Scan" | "Inspect" | "Capture" | "Done"

local TutorialFlow = {}

TutorialFlow.Steps = table.freeze({ "Scan", "Inspect", "Capture", "Done" })

function TutorialFlow.initial(completed: boolean?): Step
	return if completed then "Done" else "Scan"
end

function TutorialFlow.advance(step: Step, event: string): Step
	if step == "Done" then
		return "Done"
	end
	if event == "Captured" then
		return "Done"
	elseif event == "Revealed" then
		return "Capture"
	elseif event == "Scanned" and step == "Scan" then
		return "Inspect"
	elseif event == "Escaped" and step == "Capture" then
		return "Inspect"
	end
	return step
end

function TutorialFlow.isActive(step: Step): boolean
	return step ~= "Done"
end

return TutorialFlow
