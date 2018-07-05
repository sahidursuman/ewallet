ExUnit.start()

if System.get_env("USE_JUNIT") do
  ExUnit.configure(formatters: [JUnitFormatter, ExUnit.CLIFormatter])
end

Ecto.Adapters.SQL.Sandbox.mode(LocalLedgerDB.Repo, :manual)
