defmodule HexHub.StorageConfigTest do
  # async: false because tests share the Mnesia storage_configs table
  use ExUnit.Case, async: false

  alias HexHub.StorageConfig

  setup do
    # Reset Mnesia storage_configs table to a known default state before each test
    :mnesia.sync_transaction(fn ->
      :mnesia.delete({:storage_configs, "default"})
    end)

    # Seed a clean local config as baseline
    StorageConfig.update_config(%{
      "storage_type" => "local",
      "storage_path" => "priv/test_storage",
      "s3_bucket" => "",
      "s3_bucket_path" => "/",
      "s3_region" => "us-east-1",
      "s3_host" => "",
      "s3_port" => "443",
      "s3_scheme" => "https://",
      "s3_path_style" => "false"
    })

    :ok
  end

  describe "config/0" do
    test "returns current storage configuration" do
      config = StorageConfig.config()

      assert is_atom(config.storage_type)
      assert is_binary(config.storage_path)
      assert is_binary(config.s3_region) or is_nil(config.s3_region)
      assert is_binary(config.s3_scheme)
      assert is_boolean(config.s3_path_style)
    end

    test "has default values" do
      config = StorageConfig.config()

      assert config.storage_type == :local
      assert config.storage_path == "priv/test_storage"
      assert config.s3_region == "us-east-1"
      assert config.s3_scheme == "https://"
    end
  end

  describe "test_connection/0" do
    test "tests local storage connection" do
      StorageConfig.update_config(%{
        "storage_type" => "local",
        "storage_path" => "priv/test_storage"
      })

      result = StorageConfig.test_connection()

      assert match?({:ok, "Local storage working correctly"}, result)
    end

    test "handles S3 storage when bucket is empty" do
      StorageConfig.update_config(%{
        "storage_type" => "local",
        "storage_path" => "priv/test_storage"
      })

      # Now force the Mnesia record to have s3 type with nil bucket
      :mnesia.sync_transaction(fn ->
        :mnesia.write(
          {:storage_configs, "default", :s3, "priv/test_storage", nil, "/", "us-east-1", nil, 443,
           "https://", false, nil, nil, DateTime.to_unix(DateTime.utc_now()),
           DateTime.to_unix(DateTime.utc_now())}
        )
      end)

      StorageConfig.apply_to_app_env()

      result = StorageConfig.test_connection()

      assert match?({:error, "S3 bucket not configured"}, result)
    end
  end

  describe "update_config/1" do
    test "updates local storage configuration" do
      params = %{
        "storage_type" => "local",
        "storage_path" => "custom/storage/path"
      }

      result = StorageConfig.update_config(params)

      assert result == :ok

      config = StorageConfig.config()
      assert config.storage_type == :local
      assert config.storage_path == "custom/storage/path"
    end

    test "updates S3 storage configuration" do
      params = %{
        "storage_type" => "s3",
        "s3_bucket" => "test-bucket",
        "s3_region" => "us-west-2",
        "s3_host" => "s3.amazonaws.com",
        "s3_port" => "443",
        "s3_scheme" => "https://",
        "s3_path_style" => "false"
      }

      result = StorageConfig.update_config(params)

      assert result == :ok

      config = StorageConfig.config()
      assert config.storage_type == :s3
      assert config.s3_bucket == "test-bucket"
      assert config.s3_region == "us-west-2"
    end

    test "validates S3 configuration requires bucket" do
      params = %{
        "storage_type" => "s3",
        "s3_bucket" => ""
      }

      result = StorageConfig.update_config(params)

      assert match?({:error, "S3 bucket is required when using S3 storage"}, result)
    end

    test "persists configuration to Mnesia" do
      params = %{
        "storage_type" => "s3",
        "s3_bucket" => "persist-test",
        "s3_bucket_path" => "/packages",
        "s3_region" => "eu-west-1"
      }

      assert :ok = StorageConfig.update_config(params)

      # Read directly from Mnesia to verify persistence
      [
        {:storage_configs, "default", storage_type, _path, bucket, bucket_path, region, _, _, _,
         _, _, _, _, _}
      ] = :mnesia.dirty_read(:storage_configs, "default")

      assert storage_type == :s3
      assert bucket == "persist-test"
      assert bucket_path == "/packages"
      assert region == "eu-west-1"
    end

    test "preserves credentials when not provided in update" do
      # Set initial credentials
      StorageConfig.update_config(%{
        "storage_type" => "s3",
        "s3_bucket" => "cred-test",
        "s3_access_key_id" => "AKIATEST",
        "s3_secret_access_key" => "secret123"
      })

      # Update without providing credentials
      StorageConfig.update_config(%{
        "s3_bucket" => "cred-test-updated"
      })

      config = StorageConfig.config()
      assert config.s3_bucket == "cred-test-updated"
      assert config.s3_access_key_id == "AKIATEST"
      assert config.s3_secret_access_key == "secret123"
    end
  end
end
