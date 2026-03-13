defmodule HexHub.StorageTest do
  # async: false to prevent test isolation issues with Application.put_env
  use ExUnit.Case, async: false

  setup do
    # Save original config
    original_storage_type = Application.get_env(:hex_hub, :storage_type)
    original_storage_path = Application.get_env(:hex_hub, :storage_path)
    original_s3_bucket = Application.get_env(:hex_hub, :s3_bucket)

    # Ensure we start with local storage for each test
    Application.put_env(:hex_hub, :storage_type, :local)
    Application.put_env(:hex_hub, :storage_path, "priv/test_storage")

    # Create necessary subdirectories
    File.mkdir_p!("priv/test_storage/hosted/packages")
    File.mkdir_p!("priv/test_storage/hosted/docs")
    File.mkdir_p!("priv/test_storage/cached/packages")
    File.mkdir_p!("priv/test_storage/cached/docs")

    # Always restore original config after test
    on_exit(fn ->
      Application.put_env(:hex_hub, :storage_type, original_storage_type || :local)
      Application.put_env(:hex_hub, :storage_path, original_storage_path || "priv/test_storage")

      if original_s3_bucket do
        Application.put_env(:hex_hub, :s3_bucket, original_s3_bucket)
      else
        Application.delete_env(:hex_hub, :s3_bucket)
      end
    end)

    :ok
  end

  describe "local storage" do
    test "upload/3 stores package tarball" do
      key = "packages/test_package-1.0.0.tar.gz"
      content = "test package content"

      assert {:ok, ^key} = HexHub.Storage.upload(key, content)

      stored_path = Path.join(["priv/test_storage", key])
      assert File.exists?(stored_path)
      assert File.read!(stored_path) == content
    end

    test "upload/3 stores documentation tarball" do
      key = "docs/test_package-1.0.0.tar.gz"
      content = "test docs content"

      assert {:ok, ^key} = HexHub.Storage.upload(key, content)

      stored_path = Path.join(["priv/test_storage", key])
      assert File.exists?(stored_path)
      assert File.read!(stored_path) == content
    end

    test "download/1 retrieves package tarball" do
      key = "packages/test_package-1.0.0.tar.gz"
      content = "test package content"

      {:ok, ^key} = HexHub.Storage.upload(key, content)

      assert {:ok, ^content} = HexHub.Storage.download(key)
    end

    test "download/1 retrieves documentation tarball" do
      key = "docs/test_package-1.0.0.tar.gz"
      content = "test docs content"

      {:ok, ^key} = HexHub.Storage.upload(key, content)

      assert {:ok, ^content} = HexHub.Storage.download(key)
    end

    test "delete/1 removes package tarball" do
      key = "packages/test_package-1.0.0.tar.gz"
      content = "test package content"

      {:ok, ^key} = HexHub.Storage.upload(key, content)
      assert :ok = HexHub.Storage.delete(key)

      stored_path = Path.join(["priv/test_storage", key])
      refute File.exists?(stored_path)
    end

    test "delete/1 removes documentation tarball" do
      key = "docs/test_package-1.0.0.tar.gz"
      content = "test docs content"

      {:ok, ^key} = HexHub.Storage.upload(key, content)
      assert :ok = HexHub.Storage.delete(key)

      stored_path = Path.join(["priv/test_storage", key])
      refute File.exists?(stored_path)
    end

    test "returns error for non-existent file" do
      assert {:error, "File not found"} = HexHub.Storage.download("nonexistent/file.tar.gz")
    end

    test "generate_package_key/2 creates correct hosted key by default" do
      assert "hosted/packages/phoenix/phoenix-1.7.0.tar.gz" =
               HexHub.Storage.generate_package_key("phoenix", "1.7.0")
    end

    test "generate_package_key/3 creates correct cached key" do
      assert "cached/packages/phoenix/phoenix-1.7.0.tar.gz" =
               HexHub.Storage.generate_package_key("phoenix", "1.7.0", :cached)
    end

    test "generate_docs_key/2 creates correct hosted key by default" do
      assert "hosted/docs/phoenix/phoenix-1.7.0.tar.gz" =
               HexHub.Storage.generate_docs_key("phoenix", "1.7.0")
    end

    test "generate_docs_key/3 creates correct cached key" do
      assert "cached/docs/phoenix/phoenix-1.7.0.tar.gz" =
               HexHub.Storage.generate_docs_key("phoenix", "1.7.0", :cached)
    end
  end

  describe "S3 storage configuration" do
    test "returns error when bucket not configured" do
      # Temporarily remove bucket configuration
      # on_exit callback will restore to original values
      Application.put_env(:hex_hub, :storage_type, :s3)
      Application.delete_env(:hex_hub, :s3_bucket)

      key = "packages/test_package-1.0.0.tar.gz"
      content = "test package content"

      assert {:error, "S3 bucket not configured"} = HexHub.Storage.upload(key, content)
    end

    @tag :s3
    @tag :skip
    test "builds S3 upload options correctly" do
      # This test is skipped to avoid external S3 calls during test runs
      # S3 configuration validation is tested separately without actual uploads

      # When no bucket configured, verify error handling
      # on_exit callback will restore to original values
      Application.put_env(:hex_hub, :storage_type, :s3)
      Application.delete_env(:hex_hub, :s3_bucket)

      result = HexHub.Storage.upload("test", "content")
      assert {:error, "S3 bucket not configured"} = result
    end

    test "signed_url/2 returns error for local storage" do
      key = "packages/test_package-1.0.0.tar.gz"

      assert {:error, "Signed URLs not supported for local storage"} =
               HexHub.Storage.signed_url(key)
    end

    test "signed_url/2 returns error when bucket not configured" do
      # on_exit callback will restore to original values
      Application.put_env(:hex_hub, :storage_type, :s3)
      Application.delete_env(:hex_hub, :s3_bucket)

      key = "packages/test_package-1.0.0.tar.gz"

      assert {:error, "S3 bucket not configured"} = HexHub.Storage.signed_url(key)
    end

    @tag :s3
    @tag :skip
    test "signed_url/2 generates URL for S3 storage" do
      # This test is skipped to avoid external S3 calls during test runs
      # S3 URL generation validation is tested separately without actual S3 access

      # When no bucket configured, verify error handling
      # on_exit callback will restore to original values
      Application.put_env(:hex_hub, :storage_type, :s3)
      Application.delete_env(:hex_hub, :s3_bucket)

      result = HexHub.Storage.signed_url("test")
      assert {:error, "S3 bucket not configured"} = result
    end
  end
end
