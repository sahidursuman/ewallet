{:ok, _} = Application.ensure_all_started(:ex_machina)

if System.get_env("USE_JUNIT") do
  ExUnit.configure(formatters: [JUnitFormatter, ExUnit.CLIFormatter])
end

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(EWalletDB.Repo, :manual)
