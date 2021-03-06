defmodule CanvasAPI.Unfurl.Label do
  @moduledoc """
  A label applied to an unfurl.
  """

  defstruct icon: nil, value: nil, color: nil, background_color: nil

  @type t :: %__MODULE__{
    background_color: String.t | nil,
    color: String.t | nil,
    icon: String.t | nil,
    value: String.t | nil
  }
end
