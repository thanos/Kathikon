cover_mode? =
  case :code.which(:cover) do
    :non_existing ->
      false

    _ ->
      case :cover.modules() do
        {:error, :not_started} -> false
        _ -> true
      end
  end

exclude = if cover_mode?, do: [], else: [integration: true]

ExUnit.start(exclude: exclude)

Mox.defmock(Kathikon.Backend.Storage.Mock, for: Kathikon.Storage)
Mox.defmock(Kathikon.Scheduler.Quantum.Mock, for: Kathikon.Scheduler.Quantum.Scheduler)
Mox.defmock(Kathikon.Storage.Mnesia.Context.Mock, for: Kathikon.Storage.Mnesia.Context)

Application.put_env(:kathikon, :storage_backend, Kathikon.Storage.Mnesia)
