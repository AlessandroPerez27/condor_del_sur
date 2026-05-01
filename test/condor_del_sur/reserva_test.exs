defmodule CondorDelSur.ReservaTest do
  use ExUnit.Case
  alias CondorDelSur.Reserva

  # Helper para no repetir esto en cada test
  defp reserva_nueva, do: Reserva.nueva("R1", "P1", "1A")

  test "una reserva nueva esta pending" do
    reserva = reserva_nueva()
    assert reserva.estado == :pending
  end

  test "pendiente? retorna true si esta pending" do
    reserva = reserva_nueva()
    assert Reserva.pendiente?(reserva)
  end

  test "confirmar una reserva pending funciona" do
    reserva = reserva_nueva()
    assert {:ok, %Reserva{estado: :confirmed}} = Reserva.confirmar(reserva)
  end

  test "cancelar una reserva pending funciona" do
    reserva = reserva_nueva()
    assert {:ok, %Reserva{estado: :cancelled}} = Reserva.cancelar(reserva)
  end

  test "expirar una reserva pending funciona" do
    reserva = reserva_nueva()
    assert {:ok, %Reserva{estado: :expired}} = Reserva.expirar(reserva)
  end

  test "no se puede confirmar una reserva ya confirmed" do
    reserva = reserva_nueva()
    {:ok, reserva_confirmada} = Reserva.confirmar(reserva)
    assert {:error, :no_pendiente} = Reserva.confirmar(reserva_confirmada)
  end

  test "no se puede cancelar una reserva ya confirmed" do
    reserva = reserva_nueva()
    {:ok, reserva_confirmada} = Reserva.confirmar(reserva)
    assert {:error, :no_pendiente} = Reserva.cancelar(reserva_confirmada)
  end

  test "no se puede cancelar una reserva ya cancelled" do
    reserva = reserva_nueva()
    {:ok, reserva_cancelada} = Reserva.cancelar(reserva)
    assert {:error, :no_pendiente} = Reserva.cancelar(reserva_cancelada)
  end

  test "no se puede expirar una reserva ya cancelled" do
    reserva = reserva_nueva()
    {:ok, reserva_cancelada} = Reserva.cancelar(reserva)
    assert {:error, :no_pendiente} = Reserva.expirar(reserva_cancelada)
  end
end
