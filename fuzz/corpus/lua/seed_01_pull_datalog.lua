db:transact_script([[branch genesis { put .users["1"].name = "ada" put .users["1"].score = 9i }]])
local pv = db:pull("@0", "{.users}")
local res = db:query_datalog("find ?n where .users[?id].name = ?n")
