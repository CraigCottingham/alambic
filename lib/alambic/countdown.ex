# Copyright 2015 Serge Danzanvilliers <serge.danzanvilliers@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule Alambic.CountDown do
  @moduledoc """
  A simple countdown latch implementation useful for simple fan in scenarios.
  It is initialized with a count and clients can wait on it to be signaled
  when the count reaches 0, decrement the count or increment the count.

  It is implemented as a `GenServer`.

  In the unlikely case you need to start a named `CountDown` you can directly
  use the `GenServer.start/start_link` functions passing the required initial
  `count` as argument.
  """

  @vsn 1

  use GenServer
  alias Alambic.CountDown

  defstruct id: nil
  @type t :: %__MODULE__{id: pid}

  @doc ~S"""
  Create a CountDown object with `count` initial count.
  `count` must be a positive integer.

  ## Example

      iex> c = Alambic.CountDown.create(2)
      iex> is_nil(c.id)
      false
  """
  @spec create(integer) :: t
  def create(count) when is_integer(count) and count >= 0 do
    {:ok, pid} = GenServer.start(__MODULE__, count)
    %CountDown{id: pid}
  end

  @doc """
  Create a CountDown with `count` initial count. It is linked
  to the current process.

  ## Example

      iex> c = Alambic.CountDown.create_link(2)
      iex> Alambic.CountDown.destroy(c)
      :ok
  """
  @spec create_link(integer) :: t
  def create_link(count) when is_integer(count) and count >= 0 do
    {:ok, pid} = GenServer.start_link(__MODULE__, count)
    %CountDown{id: pid}
  end

  @doc """
  Destroy the countdown object, returning `:error` to all waiters.

  ## Example

      iex> c = Alambic.CountDown.create(2)
      iex> Alambic.CountDown.destroy(c)
      :ok
  """
  @spec destroy(t) :: :ok
  def destroy(_ = %CountDown{id: pid}) do
    GenServer.cast(pid, :destroy)
  end

  @doc "Wait for the count to reach 0."
  @spec wait(t) :: :ok | :error
  def wait(_ = %CountDown{id: pid}) do
    GenServer.call(pid, :wait, :infinity)
  end

  @doc """
  Decrease the count by one.
  Returns true if the count reached 0, false otherwise.

  ## Example

      iex> c = Alambic.CountDown.create(1)
      iex> Alambic.CountDown.signal(c)
      true
  """
  @spec signal(t) :: true | false
  def signal(_ = %CountDown{id: pid}) do
    GenServer.call(pid, :signal)
  end

  @doc """
  Increase the count by one.

  ## Example

      iex> c = Alambic.CountDown.create(0)
      iex> Alambic.CountDown.increase(c)
      iex> Alambic.CountDown.signal(c)
      true

  """
  @spec increase(t) :: :ok | :error
  def increase(_ = %CountDown{id: pid}) do
    GenServer.call(pid, :increase)
  end

  @doc """
  Reset the count to a new value.

  ## Example

      iex> c = Alambic.CountDown.create(10)
      iex> false = Alambic.CountDown.signal(c)
      iex> Alambic.CountDown.reset(c, 1)
      iex> Alambic.CountDown.signal(c)
      true
  """
  @spec reset(t, integer) :: :ok
  def reset(_ = %CountDown{id: pid}, count)
  when is_integer(count) and count >= 0 do
    GenServer.call(pid, {:reset, count})
  end

  @doc """
  Return the current count.

  ## Example

      iex> c = Alambic.CountDown.create(10)
      iex> Alambic.CountDown.count(c)
      10
  """
  @spec count(t) :: integer
  def count(_ = %CountDown{id: pid}) do
    GenServer.call(pid, :count)
  end

  # -----------------
  # Waitable protocol

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

  # -------------------
  # GenServer callbacks

  def init(count) do
    {:ok, {[], count}}
  end

  def terminate(_, {waiting, _}) do
    waiting |> Enum.each(&GenServer.reply(&1, :error))
  end

  def handle_cast(:destroy, state) do
    {:stop, :normal, state}
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
    flush_waiting(waiting)
    {:reply, true, {[], 0}}
  end

  def handle_call(:signal, _, {w, count}) do
    {:reply, false, {w, count - 1}}
  end

  def handle_call(:increase, _, {w, count}) do
    {:reply, :ok, {w, count + 1}}
  end

  def handle_call({:reset, 0}, _, {w, _}) do
    flush_waiting(w)
    {:reply, :ok, {[], 0}}
  end

  def handle_call({:reset, count}, _, {w, _}) do
    {:reply, :ok, {w, count}}
  end

  def handle_call(:count, _, {w, count}) do
    {:reply, count, {w, count}}
  end

  defp flush_waiting(waiting) do
    waiting |> Enum.each(&GenServer.reply(&1, :ok))
  end
end
