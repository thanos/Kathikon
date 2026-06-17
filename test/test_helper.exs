ExUnit.start()

Mox.defmock(Kathikon.Storage.Mock, for: Kathikon.Storage.Backend)
Mox.defmock(Kathikon.Mnesia.Mock, for: Kathikon.Mnesia.Backend)

Application.put_env(:kathikon, :storage_backend, Kathikon.Storage.Mnesia)
Application.put_env(:kathikon, :mnesia_backend, Kathikon.Mnesia.Erlang)
