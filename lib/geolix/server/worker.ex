defmodule Geolix.Server.Worker do
  @moduledoc false

  alias Geolix.Database.Loader

  use GenServer

  @behaviour :poolboy_worker

  def start_link(default \\ %{}) do
    GenServer.start_link(__MODULE__, default)
  end

  def init(state), do: {:ok, state}

  def handle_call({:lookup, ip, opts}, _, state) do
    case opts[:where] do
      nil -> {:reply, lookup_all(ip, opts), state}
      _where -> {:reply, lookup_single(ip, opts), state}
    end
  end

  defp lookup_all(ip, opts) do
    lookup_all(ip, opts, Loader.loaded_databases())
  end

  defp lookup_all(_, _, []), do: %{}

  defp lookup_all(ip, opts, databases) do
    # credo:disable-for-lines:7 Credo.Check.Refactor.MapInto
    databases
    |> Enum.map(fn database ->
      task_opts = Keyword.put(opts, :where, database)

      {database, Task.async(fn -> lookup_single(ip, task_opts) end)}
    end)
    |> Enum.into(%{}, fn {database, task} -> {database, Task.await(task)} end)
  end

  defp lookup_single(ip, opts) do
    case Loader.get_database(opts[:where]) do
      nil -> nil
      %{adapter: adapter} -> adapter.lookup(ip, opts)
    end
  end
end
