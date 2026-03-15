defmodule HexHubAdminWeb.UserController do
  use HexHubAdminWeb, :controller

  alias HexHub.ApiKeys
  alias HexHub.Users

  def index(conn, params) do
    page = String.to_integer(params["page"] || "1")
    per_page = 20

    {:ok, users} = Users.list_users()
    total_count = length(users)

    # Simple pagination
    offset = (page - 1) * per_page
    paginated_users = Enum.slice(users, offset, per_page)
    total_pages = max(ceil(total_count / per_page), 1)

    render(conn, :index,
      users: paginated_users,
      page: page,
      total_pages: total_pages,
      total_count: total_count
    )
  end

  def show(conn, %{"username" => username}) do
    case Users.get_user(username) do
      {:ok, user} ->
        # Get packages where user is an owner (simplified for now)
        user_packages = []

        # Load API tokens for this user
        {:ok, tokens} = ApiKeys.list_keys(user.username)

        render(conn, :show,
          user: user,
          packages: user_packages,
          tokens: tokens
        )

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "User not found")
        |> redirect(to: ~p"/users")
    end
  end

  def new(conn, _params) do
    render(conn, :new, changeset: nil)
  end

  def create(conn, %{"user" => user_params}) do
    username = user_params["username"]
    email = user_params["email"]
    password = user_params["password"]

    case Users.create_user(username, email, password) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "User #{user.username} created successfully!")
        |> redirect(to: ~p"/users/#{user.username}")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to create user: #{reason}")
        |> redirect(to: ~p"/users/new")
    end
  end

  def edit(conn, %{"username" => username}) do
    case Users.get_user(username) do
      {:ok, user} ->
        render(conn, :edit, user: user, changeset: nil)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "User not found")
        |> redirect(to: ~p"/users")
    end
  end

  def update(conn, %{"username" => username, "user" => user_params}) do
    # Check if this is a system user - block modification
    if Users.is_system_user?(username) do
      conn
      |> put_flash(:error, "System users cannot be modified")
      |> redirect(to: ~p"/users/#{username}")
    else
      case Users.get_user(username) do
        {:ok, user} ->
          # Handle different types of updates
          update_result =
            cond do
              user_params["email"] && user_params["email"] != user.email ->
                Users.update_email(username, user_params["email"])

              user_params["password"] && user_params["password"] != "" ->
                Users.update_password(username, user_params["password"])

              true ->
                {:error, "No changes provided"}
            end

          case update_result do
            {:ok, updated_user} ->
              conn
              |> put_flash(:info, "User #{updated_user.username} updated successfully!")
              |> redirect(to: ~p"/users/#{updated_user.username}")

            {:error, reason} ->
              conn
              |> put_flash(:error, "Failed to update user: #{reason}")
              |> redirect(to: ~p"/users/#{username}/edit")
          end

        {:error, :not_found} ->
          conn
          |> put_flash(:error, "User not found")
          |> redirect(to: ~p"/users")
      end
    end
  end

  def delete(conn, %{"username" => username}) do
    # Check if this is a system user - block deletion
    if Users.is_system_user?(username) do
      conn
      |> put_flash(:error, "System users cannot be deleted")
      |> redirect(to: ~p"/users")
    else
      case Users.delete_user(username) do
        :ok ->
          conn
          |> put_flash(:info, "User #{username} deleted successfully")
          |> redirect(to: ~p"/users")

        {:error, reason} ->
          conn
          |> put_flash(:error, "Failed to delete user: #{reason}")
          |> redirect(to: ~p"/users")
      end
    end
  end
end
