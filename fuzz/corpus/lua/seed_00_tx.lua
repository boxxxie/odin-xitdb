local tx = db:tx_init(nil, false)
tx:put(".users.alice.age", xitdb.uint(30)):commit()
assert(db:get_uint("@0.users.alice.age") == 30)
