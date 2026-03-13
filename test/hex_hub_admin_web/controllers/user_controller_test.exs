defmodule HexHubAdminWeb.UserControllerTest do
  use HexHubAdminWeb.ConnCase

  alias HexHub.Users

  describe "anonymous user in user list" do
    setup do
      # Ensure anonymous user exists
      Users.ensure_anonymous_user()
      :ok
    end

    test "shows anonymous user in user list", %{conn: conn} do
      conn = get(conn, ~p"/users")

      response = html_response(conn, 200)
      assert response =~ "anonymous"
    end

    test "displays system user badge for anonymous user", %{conn: conn} do
      conn = get(conn, ~p"/users")

      response = html_response(conn, 200)
      assert response =~ "System"
    end

    test "shows protected button instead of delete for anonymous user", %{conn: conn} do
      conn = get(conn, ~p"/users")

      response = html_response(conn, 200)
      assert response =~ "Protected"
    end
  end

  describe "anonymous user show page" do
    setup do
      Users.ensure_anonymous_user()
      :ok
    end

    test "shows system user badge on show page", %{conn: conn} do
      conn = get(conn, ~p"/users/anonymous")

      response = html_response(conn, 200)
      assert response =~ "System User"
    end

    test "edit button is disabled for system user", %{conn: conn} do
      conn = get(conn, ~p"/users/anonymous")

      response = html_response(conn, 200)
      # Check for disabled buttons (disabled attribute)
      assert response =~ "disabled"
      assert response =~ "System users cannot be edited"
    end

    test "delete button is disabled for system user", %{conn: conn} do
      conn = get(conn, ~p"/users/anonymous")

      response = html_response(conn, 200)
      assert response =~ "System users cannot be deleted"
    end
  end

  describe "delete prevention for anonymous user" do
    setup do
      Users.ensure_anonymous_user()
      :ok
    end

    test "prevents deletion of anonymous user", %{conn: conn} do
      conn = delete(conn, ~p"/users/anonymous")

      # Should redirect with error flash
      assert redirected_to(conn) == ~p"/users"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "cannot be deleted"

      # User should still exist
      assert {:ok, _user} = Users.get_user("anonymous")
    end
  end

  describe "edit prevention for anonymous user" do
    setup do
      Users.ensure_anonymous_user()
      :ok
    end

    test "edit page shows warning for system user", %{conn: conn} do
      conn = get(conn, ~p"/users/anonymous/edit")

      response = html_response(conn, 200)
      assert response =~ "System users cannot be modified"
      assert response =~ "protected"
    end

    test "prevents update of anonymous user", %{conn: conn} do
      conn =
        put(conn, ~p"/users/anonymous", %{
          "user" => %{"email" => "newemail@example.com"}
        })

      # Should redirect with error flash
      assert redirected_to(conn) == ~p"/users/anonymous"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "cannot be modified"

      # User should still have original email
      {:ok, user} = Users.get_user("anonymous")
      assert user.email == "anonymous@hexhub.local"
    end
  end

  describe "regular user operations" do
    test "allows deletion of regular users", %{conn: conn} do
      # Create a regular user
      {:ok, _user} = Users.create_user("regularuser", "regular@example.com", "password123")

      conn = delete(conn, ~p"/users/regularuser")

      # Should redirect with success flash
      assert redirected_to(conn) == ~p"/users"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "deleted"

      # User should be deleted
      assert {:error, :not_found} = Users.get_user("regularuser")
    end

    test "does not show system badge for regular users", %{conn: conn} do
      # Create a regular user
      {:ok, _user} = Users.create_user("regularuser", "regular@example.com", "password123")

      conn = get(conn, ~p"/users/regularuser")

      response = html_response(conn, 200)
      refute response =~ "System User"
    end
  end
end
