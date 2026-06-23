ExUnit.start()

Mox.defmock(Kathikon.Storage.Mock, for: Kathikon.Storage)
Mox.defmock(Kathikon.Scheduler.Quantum.Mock, for: Kathikon.Scheduler.Quantum.Scheduler)
Mox.defmock(Kathikon.Storage.Mnesia.Context.Mock, for: Kathikon.Storage.Mnesia.Context)

Application.put_env(:kathikon, :storage_backend, Kathikon.Storage.Mnesia)
