defmodule CondorDelSur.Asiento do
  # Estados válidos de un asiento como constante del módulo
  @estados [:available, :reserved, :confirmed]

  # Campos del struct estado tiene valor por defecto :available
  defstruct [:id, :fila, :columna, estado: :available]

  # Crea un asiento nuevo, siempre disponible
  def nuevo(id, fila, columna) do
    %__MODULE__{id: id, fila: fila, columna: columna}
  end

  # Cambia el estado solo si nuevo_estado es uno de los vlidos
  def transicion(%__MODULE__{} = asiento, nuevo_estado) when nuevo_estado in @estados do
    {:ok, %{asiento | estado: nuevo_estado}}
  end

  # Cualquier otro caso retorna error
  def transicion(_, _), do: {:error, :estado_invalido}

  # Solo matchea si el estado es exactamente :available
  def disponible?(%__MODULE__{estado: :available}), do: true
  def disponible?(_), do: false
end
