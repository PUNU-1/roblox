-- Повтор вызова в pcall (блок 6): DataStore и телепорт иногда отвечают ошибкой с первого раза.
-- Общий для музея и хаба (hub.project.json подключает этот файл).

local Retry = {}

-- Вызывает fn до attempts раз, между попытками ждёт delay, 2 × delay, … Возвращает (удалось, результат или ошибка).
function Retry.call(attempts: number, delay: number, fn: () -> any): (boolean, any)
	local lastError: any = nil
	local count = math.max(1, attempts)
	for attempt = 1, count do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		if attempt < count then
			task.wait(delay * attempt)
		end
	end
	return false, lastError
end

return Retry
