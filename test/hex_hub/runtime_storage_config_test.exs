defmodule HexHub.RuntimeStorageConfigTest do
  use ExUnit.Case, async: false

  alias HexHub.StorageConfig

  @storage_keys [:storage_type, :storage_path, :s3_bucket, :s3_bucket_path, :s3_region]
  @aws_keys [:access_key_id, :secret_access_key, :region, :s3]
  @environment %{
    "DATABASE_BACKEND" => "mnesia",
    "SECRET_KEY_BASE" => String.duplicate("runtime-storage-test-", 4),
    "STORAGE_TYPE" => "s3",
    "S3_BUCKET" => "runtime-region-test",
    "AWS_REGION" => "us-east-1",
    "AWS_ACCESS_KEY_ID" => "runtime-test-key",
    "AWS_SECRET_ACCESS_KEY" => "runtime-test-secret",
    "AWS_S3_HOST" => "",
    "AWS_S3_SCHEME" => "https",
    "AWS_S3_PORT" => "443",
    "AWS_S3_PATH_STYLE" => "false"
  }

  setup do
    environment = Map.new(@environment, fn {key, _value} -> {key, System.get_env(key)} end)

    application_env =
      for {app, keys} <- [hex_hub: @storage_keys, ex_aws: @aws_keys],
          key <- keys,
          do: {app, key, Application.fetch_env(app, key)}

    records = HexHub.Database.dirty_read(:storage_configs, "default")

    on_exit(fn ->
      Enum.each(environment, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)

      Enum.each(application_env, fn
        {app, key, {:ok, value}} -> Application.put_env(app, key, value)
        {app, key, :error} -> Application.delete_env(app, key)
      end)

      HexHub.Database.sync_transaction(fn ->
        HexHub.Database.delete({:storage_configs, "default"})
        Enum.each(records, &HexHub.Database.write/1)
      end)
    end)

    System.put_env(@environment)

    assert {:atomic, :ok} =
             HexHub.Database.sync_transaction(fn ->
               HexHub.Database.delete({:storage_configs, "default"})
             end)

    :ok
  end

  test "fresh storage seeds the runtime region instead of the production build region" do
    load_production_storage_config("ap-northeast-1")

    assert :ok = StorageConfig.init_default_config()
    assert %{storage_type: :s3, s3_region: "ap-northeast-1"} = StorageConfig.config()
    assert_effective_region("ap-northeast-1")

    # Starting again with a different environment retains the persisted configuration.
    load_production_storage_config("eu-west-1")
    assert :ok = StorageConfig.init_default_config()
    assert_effective_region("ap-northeast-1")
  end

  test "startup preserves an explicitly saved administrator region" do
    assert :ok =
             StorageConfig.update_config(%{
               "storage_type" => "s3",
               "s3_bucket" => "saved-region-test",
               "s3_region" => "eu-central-1"
             })

    load_production_storage_config("ap-northeast-1")

    assert :ok = StorageConfig.init_default_config()
    assert %{s3_bucket: "saved-region-test", s3_region: "eu-central-1"} = StorageConfig.config()
    assert_effective_region("eu-central-1")
  end

  defp load_production_storage_config(runtime_region) do
    System.put_env("AWS_REGION", "us-east-1")
    build_config = Config.Reader.read!("config/prod.exs", env: :prod)
    System.put_env("AWS_REGION", runtime_region)
    runtime_config = Config.Reader.read!("config/runtime.exs", env: :prod)
    config = Config.Reader.merge(build_config, runtime_config)

    for {app, keys} <- [hex_hub: @storage_keys, ex_aws: @aws_keys],
        {key, value} <- Keyword.take(config[app], keys) do
      Application.put_env(app, key, value)
    end
  end

  defp assert_effective_region(region) do
    assert Application.get_env(:hex_hub, :s3_region) == region
    assert Application.get_env(:ex_aws, :region) == region
    assert ExAws.Config.new(:s3).region == region
  end
end
