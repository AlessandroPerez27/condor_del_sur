defmodule CondorDelSur.Vuelo do
  # Solo datos del vuelo, sin lógica de procesos
  defstruct [:id, :origen, :destino, :fecha]

  # Crea un vuelo nuevo
  def nuevo(id, origen, destino, fecha) do
    %__MODULE__{id: id, origen: origen, destino: destino, fecha: fecha}
  end
end
