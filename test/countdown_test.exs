defmodule Alambic.CountDown.Tests do
  use ExUnit.Case
  doctest Alambic.CountDown
  alias Alambic.CountDown

  setup context do
    if count = context[:count] do
      c = CountDown.create(count)
      on_exit fn -> CountDown.destroy(c) end
      {:ok, c: c}
    else
      :ok
    end
  end

  test "can_create_CountDown" do
    c = CountDown.create(10)
    %CountDown{id: pid} = c
    assert is_pid(pid)
    CountDown.destroy(c)

    c = CountDown.create(0)
    %CountDown{id: pid} = c
    assert is_pid(pid)
    CountDown.wait(c)
    CountDown.destroy(c)
  end

  test "cannot_create_negative_CountDown" do
    catch_error CountDown.create(-1)
  end

  @tag count: 2
  test "signal_CountDown", %{c: c} do
    refute CountDown.signal(c)
    assert CountDown.signal(c)
  end

  @tag count: 1
  test "signaled_do_not_wait", %{c: c} do
    CountDown.signal(c)
    assert :ok = CountDown.wait(c)
  end

  @tag count: 1
  test "wait", %{c: c} do
    me = self()
    spawn fn -> send(me, CountDown.wait(c)) end
    spawn fn -> send(me, CountDown.wait(c)) end

    refute_receive _, 500

    true = CountDown.signal(c)

    assert_receive :ok
    assert_receive :ok
  end

  test "destroy" do
    c = CountDown.create(1)
    me = self()
    spawn fn -> send(me, CountDown.wait(c)) end
    spawn fn -> send(me, CountDown.wait(c)) end

    refute_receive _, 100

    CountDown.destroy(c)

    assert_receive :error
    assert_receive :error
  end

  @tag count: 1
  test "reset countdown", %{c: c} do
    me = self()
    spawn fn -> send(me, CountDown.wait(c)) end

    refute_receive _, 100

    :ok = CountDown.reset(c, 10)
    false = CountDown.signal(c)

    refute_receive _, 100
  end

  @tag count: 10
  test "reset countdown to 0", %{c: c} do
    me = self()
    spawn fn -> send(me, CountDown.wait(c)) end
    spawn fn -> send(me, CountDown.wait(c)) end
    spawn fn -> send(me, CountDown.wait(c)) end

    refute_receive _, 100

    :ok = CountDown.reset(c, 0)

    assert_receive :ok, 100
    assert_receive :ok, 100
    assert_receive :ok, 100

    :error = CountDown.signal(c)
  end

  @tag count: 1
  test "waitable countdown", %{c: c} do
    refute Alambic.Waitable.free?(c)

    me = self()
    spawn(fn -> send(me, Alambic.Waitable.wait(c)) end)

    refute_receive _, 200

    CountDown.signal(c)
    assert_receive :ok, 100
  end

  @tag count: 0
  test "increase countdown", %{c: c} do
    me = self()
    spawn fn -> send(me, CountDown.wait(c)) end

    assert_receive _, 100

    CountDown.increase(c)

    spawn fn -> send(me, CountDown.wait(c)) end
    refute_receive _, 100

    CountDown.signal(c)
    assert_receive _, 100
  end
end
