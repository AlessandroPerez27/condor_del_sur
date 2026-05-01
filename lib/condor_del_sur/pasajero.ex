defmodule CondorDelSur.Pasajero do
  # Solo datos, sin lógica de procesos
  defstruct [:id, :nombre, :email]

  # Crea un pasajero nuevo
  def nuevo(id, nombre, email) do
    %__MODULE__{id: id, nombre: nombre, email: email}
  end
end
