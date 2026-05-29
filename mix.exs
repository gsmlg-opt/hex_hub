defmodule HexHub.MixProject do
  use Mix.Project

  def project do
    [
      app: :hex_hub,
      version: "1.0.11",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: dialyzer(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      releases: [
        hex_hub: [
          include_executables_for: [:unix],
          steps: [:assemble, :tar],
          applications: [
            hex_hub: :permanent
          ]
        ]
      ]
    ]
  end

  def application do
    [
      mod: {HexHub.Application, []},
      extra_applications: [:logger, :runtime_tools, :mnesia]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    common_deps = [
      {:phoenix, "~> 1.8.0-rc.4", override: true},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0-rc.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:phoenix_duskmoon, "~> 9.1"},
      {:volt, "~> 0.14.0"},
      {:npm, "~> 0.7.4", runtime: false},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:bcrypt_elixir, "~> 3.0"},
      {:uuid, "~> 1.1"},
      {:libcluster, "~> 3.3"},
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},
      {:sweet_xml, "~> 0.7"},
      {:mox, "~> 1.1", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:nimble_totp, "~> 1.0"},
      {:qr_code, "~> 3.0"},
      {:yaml_elixir, "~> 2.11"}
    ]

    common_deps ++ quickbeam_source_deps()
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      flags: [:error_handling, :underspecs],
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "quickbeam.compile", "assets.setup", "assets.build"],
      test: ["test"],
      lint: ["credo --strict", "dialyzer"],
      "quickbeam.compile": quickbeam_compile_alias(),
      "assets.setup": ["npm.install"],
      "assets.build": [
        "cmd mix volt.build hex_hub --tailwind --no-hash --no-minify",
        "cmd mix volt.build hex_hub_admin --tailwind --no-hash --no-minify"
      ],
      "assets.deploy": [
        "cmd mix volt.build hex_hub --tailwind",
        "cmd mix volt.build hex_hub_admin --tailwind",
        "phx.digest"
      ]
    ]
  end

  defp quickbeam_source_deps do
    if quickbeam_source_build?() do
      [{:zigler, "~> 0.15.2", runtime: false}]
    else
      []
    end
  end

  defp quickbeam_compile_alias do
    if quickbeam_source_build?() do
      [
        "cmd elixir scripts/patch_quickbeam_targets.exs",
        "cmd mise exec zig@0.15.2 -- mix deps.compile zigler",
        "cmd mise exec zig@0.15.2 -- env QUICKBEAM_BUILD=1 mix deps.compile quickbeam"
      ]
    else
      []
    end
  end

  defp quickbeam_source_build? do
    build_host() == {"x86_64", :darwin}
  end

  defp build_host do
    system = :erlang.system_info(:system_architecture) |> to_string()
    arch = system |> String.split("-") |> hd()

    os =
      cond do
        String.contains?(system, "linux") -> :linux
        String.contains?(system, "darwin") -> :darwin
        true -> :unknown
      end

    {arch, os}
  end
end
