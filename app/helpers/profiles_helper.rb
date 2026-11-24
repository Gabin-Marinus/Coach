module ProfilesHelper
  # Turns a stored key ("lightly_active") into its label from User ("Lightly active ...")
  def option_label(options, value, blank: "–")
    value.present? ? options[value] : blank
  end

  # Same for checkbox fields, e.g. ["dairy", "eggs"] => "Dairy, Eggs"
  def option_labels(options, values, blank: "None")
    values.present? ? values.map { |v| options[v] }.join(", ") : blank
  end
end
