module ProfilesHelper
  # Turns a stored key ("lightly_active") into its label from User ("Lightly active ...")
  def option_label(options, value, blank: "–")
    value.present? ? options[value] : blank
  end

  # Same for checkbox fields, e.g. ["dairy", "eggs"] => "Dairy, Eggs"
  def option_labels(options, values, blank: "None")
    values.present? ? values.map { |v| options[v] }.join(", ") : blank
  end

  # "Active", "Ended" or "Archived" pill for a plan
  def plan_status_badge(plan)
    label, css = if plan.status == "archived" then ["Archived", "text-bg-secondary"]
                 elsif plan.ended? then ["Ended", "text-bg-secondary"]
                 else ["Active", "text-bg-success"]
                 end
    content_tag(:span, label, class: "badge rounded-pill align-middle plan-badge #{css}")
  end
end
