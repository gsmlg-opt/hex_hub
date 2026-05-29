defmodule HexHubAdminWeb.AdminComponents do
  @moduledoc false

  use Phoenix.Component
  use PhoenixDuskmoon.Component

  attr(:id, :any, default: nil)
  attr(:label, :string, required: true)
  attr(:icon, :string, required: true)
  attr(:variant, :string, default: "ghost")
  attr(:size, :string, default: "sm")
  attr(:shape, :string, default: "square")
  attr(:class, :any, default: nil)
  attr(:tooltip_position, :string, default: "left")
  attr(:disabled, :boolean, default: false)
  attr(:navigate, :string, default: nil)
  attr(:patch, :string, default: nil)
  attr(:href, :any, default: nil)
  attr(:replace, :boolean, default: false)
  attr(:confirm, :string, default: "")
  attr(:confirm_title, :string, default: "")
  attr(:confirm_text, :string, default: "Yes")
  attr(:cancel_text, :string, default: "Cancel")
  attr(:confirm_class, :any, default: nil)
  attr(:cancel_class, :any, default: nil)
  attr(:show_cancel_action, :boolean, default: true)

  attr(:rest, :global,
    include: ~w(phx-click phx-target phx-value-id phx-disable-with name value type form title)
  )

  def admin_table_action(assigns) do
    ~H"""
    <.dm_tooltip content={@label} position={@tooltip_position} class="admin-table-action-tooltip">
      <.dm_btn
        id={@id}
        navigate={@navigate}
        patch={@patch}
        href={@href}
        replace={@replace}
        variant={@variant}
        size={@size}
        shape={@shape}
        disabled={@disabled}
        class={["admin-table-action-button", @class]}
        aria-label={@label}
        confirm={@confirm}
        confirm_title={@confirm_title}
        confirm_text={@confirm_text}
        cancel_text={@cancel_text}
        confirm_class={@confirm_class}
        cancel_class={@cancel_class}
        show_cancel_action={@show_cancel_action}
        {@rest}
      >
        <.dm_mdi name={@icon} class="h-4 w-4" />
        <span class="sr-only">{@label}</span>
      </.dm_btn>
    </.dm_tooltip>
    """
  end
end
