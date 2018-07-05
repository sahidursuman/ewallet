if System.get_env("USE_JUNIT") do
  ExUnit.configure(formatters: [JUnitFormatter, ExUnit.CLIFormatter])
end

ExUnit.start()
