defmodule HexHubAdminWeb.PublishConfigControllerTest do
  use HexHubAdminWeb.ConnCase

  alias HexHub.PublishConfig

  describe "index/2" do
    test "shows current config with disabled status by default", %{conn: conn} do
      conn = get(conn, ~p"/publish-config")

      response = html_response(conn, 200)
      assert response =~ "Anonymous Publishing"
      assert response =~ "Disabled"
    end

    test "shows enabled status when anonymous publishing is enabled", %{conn: conn} do
      :ok = PublishConfig.update_config(%{"enabled" => true})

      conn = get(conn, ~p"/publish-config")

      response = html_response(conn, 200)
      assert response =~ "Anonymous Publishing"
      assert response =~ "Enabled"
    end

    test "displays toggle form", %{conn: conn} do
      conn = get(conn, ~p"/publish-config")

      response = html_response(conn, 200)
      assert response =~ "form"
      assert response =~ "publish-config"
    end
  end

  describe "update/2" do
    test "enables anonymous publishing", %{conn: conn} do
      conn = put(conn, ~p"/publish-config", %{"publish_config" => %{"enabled" => "true"}})

      assert redirected_to(conn) == ~p"/publish-config"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "updated"
      assert PublishConfig.anonymous_publishing_enabled?() == true
    end

    test "disables anonymous publishing", %{conn: conn} do
      # First enable it
      :ok = PublishConfig.update_config(%{"enabled" => true})
      assert PublishConfig.anonymous_publishing_enabled?() == true

      # Then disable it
      conn = put(conn, ~p"/publish-config", %{"publish_config" => %{"enabled" => "false"}})

      assert redirected_to(conn) == ~p"/publish-config"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "updated"
      assert PublishConfig.anonymous_publishing_enabled?() == false
    end

    test "shows success flash message after toggling", %{conn: conn} do
      conn = put(conn, ~p"/publish-config", %{"publish_config" => %{"enabled" => "true"}})

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "successfully"
    end
  end

  describe "config persistence" do
    test "config persists across requests", %{conn: conn} do
      # Enable via update
      conn = put(conn, ~p"/publish-config", %{"publish_config" => %{"enabled" => "true"}})
      assert redirected_to(conn) == ~p"/publish-config"

      # Verify persisted by reading back
      conn =
        get(
          build_conn()
          |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
          |> Plug.Test.init_test_session(%{}),
          ~p"/publish-config"
        )

      response = html_response(conn, 200)
      assert response =~ "Enabled"
    end

    test "config change is reflected immediately", %{conn: conn} do
      # Start disabled
      assert PublishConfig.anonymous_publishing_enabled?() == false

      # Enable via controller
      _conn = put(conn, ~p"/publish-config", %{"publish_config" => %{"enabled" => "true"}})

      # Should be enabled now
      assert PublishConfig.anonymous_publishing_enabled?() == true
    end
  end
end
