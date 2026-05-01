defmodule CondorDelSur.Reserva do
  defstruct [:id, :id_pasajero, :id_asiento, :creada_en, estado: :pending]

  def nueva(id, id_pasajero, id_asiento) do
    %__MODULE__{
      id: id,
      id_pasajero: id_pasajero,
      id_asiento: id_asiento,
      creada_en: :os.system_time(:second)
    }
  end

  # Solo acepta reservas pendientes, cualquier otro estado retorna error
  def confirmar(%__MODULE__{estado: :pending} = reserva) do
    {:ok, %{reserva | estado: :confirmed}}
  end

  def confirmar(_), do: {:error, :no_pendiente}

  def cancelar(%__MODULE__{estado: :pending} = reserva) do
    {:ok, %{reserva | estado: :cancelled}}
  end

  def cancelar(_), do: {:error, :no_pendiente}

  def expirar(%__MODULE__{estado: :pending} = reserva) do
    {:ok, %{reserva | estado: :expired}}
  end

  def expirar(_), do: {:error, :no_pendiente}

  # Solo matchea si el estado es exactamente :pending
  def pendiente?(%__MODULE__{estado: :pending}), do: true
  def pendiente?(_), do: false
end
