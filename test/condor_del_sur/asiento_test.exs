defmodule CondorDelSur.AsientoTest do
  use ExUnit.Case
  alias CondorDelSur.Asiento

  test "un asiento nuevo esta available" do
    asiento = Asiento.nuevo("1A", 1, "A")
    assert asiento.estado == :available
  end

  test "disponible? retorna true si esta available" do
    asiento = Asiento.nuevo("1A", 1, "A")
    assert Asiento.disponible?(asiento)
  end

  test "disponible? retorna false si esta reserved" do
    asiento = Asiento.nuevo("1A", 1, "A")
    {:ok, asiento_reservado} = Asiento.transicion(asiento, :reserved)
    refute Asiento.disponible?(asiento_reservado)
  end

  test "transicion a estado valido funciona" do
    asiento = Asiento.nuevo("1A", 1, "A")
    assert {:ok, %Asiento{estado: :reserved}} = Asiento.transicion(asiento, :reserved)
  end

  test "transicion a estado invalido retorna error" do
    asiento = Asiento.nuevo("1A", 1, "A")
    assert {:error, :estado_invalido} = Asiento.transicion(asiento, :volando)
  end
end
