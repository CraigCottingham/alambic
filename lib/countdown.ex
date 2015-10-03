defmodule Alambic.CountDown do
  @moduledoc """
  A simple countdown latch implementation useful for simple fan in scenarios.
  It is initialized with a count and clients can wait on it to be signaled
  when the count reaches 0.

  It is implemented as a GenServer.
  """

  use GenServer
  alias Alambic.CountDown

  defstruct id: nil
  @type t :: %__MODULE__{id: pid}

  @doc ~S"""
  Create a CountDown object with `count` initial count.
  `count` must be a strictly positive integer.
  """
  @spec create(integer) :: t
  def create(count) when is_integer(count) and count > 0 do
    {:ok, pid} = GenServer.start(__MODULE__, count)
    %CountDown{id: pid}
  end

  @doc """
  Create a CountDown with `count`initial count. It is linked
  to the current process.
  """
  @spec create_link(integer) :: t
  def create_link(count) when is_integer(count) and count > 0 do
    {:ok, pid} = GenServer.start(__MODULE__, count)
    %CountDown{id: pid}
  end

  @doc "Destroy the countdown object, returning `:error` to all waiters."
  @spec destroy(t) :: :ok
  def destroy(_ = %CountDown{id: pid}) do
    GenServer.cast(pid, :destroy)
  end

  @doc "Wait for the ocunt to reach."
  @spec wait(t) :: :ok | :error
  def wait(_ = %CountDown{id: pid}) do
    GenServer.call(pid, :wait, :infinity)
  end

  @doc "Decrease the count by one."
  @spec signal(t) :: :ok | :error
  def signal(_ = %CountDown{id: pid}) do
    GenServer.call(pid, :signal)
  end

  @doc "Reset the count to a new value."
  @spec reset(t, integer) :: :ok
  def reset(_ = %CountDown{id: pid}, count)
  when is_integer(count) and count > 0 do
    GenServer.call(pid, {:reset, count})
  end

  @doc "Return the current count."
  @spec count(t) :: integer
  def count(_ = %CountDown{id: pid}) do
    GenServer.call(pid, :count)
  end

  ############
  ## Protocols

  defimpl Alambic.Waitable, for: CountDown do
    @spec wait(CountDown.t) :: :ok | :error
    def wait(countdown) do
      CountDown.wait(countdown)
    end

    @spec free?(CountDown.t) :: true | false
    def free?(countdown) do
      CountDown.count(countdown) == 0
    end
  end

  ######################
  ## GenServer callbacks

  def init(count) do
    {:ok, {[], count}}
  end

  def terminate({:shutdown, :destroyed}, {waiting, _}) do
    waiting |> Enum.each(&GenServer.reply(&1, :error))
  end

  def handle_cast(:destroy, state) do
    {:stop, {:shutdown, :destroyed}, state}
  end

  def handle_call(:wait, _, state = {[], 0}) do
    {:reply, :ok, state}
  end

  def handle_call(:wait, from, {waiting, count}) do
    {:noreply, {[from | waiting], count}}
  end

  def handle_call(:signal, _, state = {[], 0}) do
    {:reply, :error, state}
  end

  def handle_call(:signal, _, {waiting, 1}) do
    waiting |> Enum.each(&GenServer.reply(&1, :ok))
    {:reply, true, {[], 0}}
  end

  def handle_call(:signal, _, {w, count}) do
    {:reply, false, {w, count - 1}}
  end

  def handle_call({:reset, count}, _, {w, _}) do
    {:reply, :ok, {w, count}}
  end

  def handle_call(:count, _, {w, count}) do
    {:reply, count, {w, count}}
  end
end
