defmodule HexHub.PublishConfigTest do
  use ExUnit.Case, async: false

  alias HexHub.PublishConfig

  setup do
    # Clear the publish_configs table before each test
    HexHub.Database.clear_table(:publish_configs)
    :ok
  end

  describe "get_config/0" do
    test "returns default config when no config exists" do
      config = PublishConfig.get_config()

      assert config.id == "default"
      assert config.enabled == false
      assert %DateTime{} = config.inserted_at
      assert %DateTime{} = config.updated_at
    end

    test "returns stored config when it exists" do
      # First update the config
      :ok = PublishConfig.update_config(%{"enabled" => true})

      config = PublishConfig.get_config()

      assert config.id == "default"
      assert config.enabled == true
    end
  end

  describe "update_config/1" do
    test "updates config with string keys" do
      assert :ok = PublishConfig.update_config(%{"enabled" => true})

      config = PublishConfig.get_config()
      assert config.enabled == true
    end

    test "updates config with atom keys" do
      assert :ok = PublishConfig.update_config(%{enabled: true})

      config = PublishConfig.get_config()
      assert config.enabled == true
    end

    test "updates config with string 'true' value" do
      assert :ok = PublishConfig.update_config(%{"enabled" => "true"})

      config = PublishConfig.get_config()
      assert config.enabled == true
    end

    test "updates config with string 'false' value" do
      # First enable it
      :ok = PublishConfig.update_config(%{"enabled" => true})

      # Then disable it
      assert :ok = PublishConfig.update_config(%{"enabled" => "false"})

      config = PublishConfig.get_config()
      assert config.enabled == false
    end

    test "preserves inserted_at when updating" do
      # Create initial config
      :ok = PublishConfig.update_config(%{"enabled" => false})
      original_config = PublishConfig.get_config()

      # Wait a bit and update
      Process.sleep(10)
      :ok = PublishConfig.update_config(%{"enabled" => true})
      updated_config = PublishConfig.get_config()

      assert original_config.inserted_at == updated_config.inserted_at
      assert DateTime.compare(updated_config.updated_at, original_config.updated_at) in [:gt, :eq]
    end
  end

  describe "anonymous_publishing_enabled?/0" do
    test "returns false by default" do
      assert PublishConfig.anonymous_publishing_enabled?() == false
    end

    test "returns true when enabled" do
      :ok = PublishConfig.update_config(%{"enabled" => true})

      assert PublishConfig.anonymous_publishing_enabled?() == true
    end

    test "returns false when disabled" do
      :ok = PublishConfig.update_config(%{"enabled" => true})
      :ok = PublishConfig.update_config(%{"enabled" => false})

      assert PublishConfig.anonymous_publishing_enabled?() == false
    end
  end

  describe "init_default_config/0" do
    test "creates default config when none exists" do
      assert :ok = PublishConfig.init_default_config()

      config = PublishConfig.get_config()
      assert config.enabled == false
    end

    test "does not overwrite existing config" do
      # Set enabled to true
      :ok = PublishConfig.update_config(%{"enabled" => true})

      # Call init_default_config
      assert :ok = PublishConfig.init_default_config()

      # Config should still be enabled
      config = PublishConfig.get_config()
      assert config.enabled == true
    end
  end
end
