defmodule HexHub.BuildInfo do
  @moduledoc "Build metadata captured at compilation and available in releases."

  env = fn key ->
    case System.get_env(key) do
      nil -> nil
      value -> if String.trim(value) == "", do: nil, else: String.trim(value)
    end
  end

  git = fn args ->
    case System.find_executable("git") do
      nil ->
        nil

      executable ->
        case System.cmd(executable, args, stderr_to_stdout: true) do
          {output, 0} ->
            if String.trim(output) == "", do: nil, else: String.trim(output)

          {_output, _status} ->
            nil
        end
    end
  end

  git_sha = env.("HEX_HUB_GIT_SHA") || git.(["rev-parse", "HEAD"])

  git_ref =
    env.("HEX_HUB_GIT_REF") ||
      git.(["symbolic-ref", "--quiet", "--short", "HEAD"]) ||
      git.(["describe", "--tags", "--exact-match", "HEAD"]) || git_sha

  default_built_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  @info [
    version: Mix.Project.config()[:version],
    environment: Mix.env(),
    development: Mix.env() == :dev,
    git_ref: git_ref,
    git_sha: git_sha,
    built_at: env.("HEX_HUB_BUILD_TIME") || default_built_at,
    released_at: env.("HEX_HUB_RELEASE_TIME")
  ]

  @spec info() :: map()
  def info, do: Map.new(@info)
end
