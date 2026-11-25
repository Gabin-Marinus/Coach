module PagesHelper
  RING_CIRCUMFERENCE = 289 # 2 * PI * r (r = 46 in the nutrition ring SVG)

  def greeting(time = Time.current)
    case time.hour
    when 5..11 then "Good morning"
    when 12..17 then "Good afternoon"
    else "Good evening"
    end
  end

  # Users have no name column yet, so use the start of their email: "gabin.m@..." => "Gabin"
  def display_name(user)
    user.email.split("@").first.split(/[._\-+]/).first.capitalize
  end

  # 0..100, never divides by zero
  def percent_of(part, whole)
    return 0 unless whole.to_f.positive?

    [(part * 100.0 / whole).round, 100].min
  end

  def ring_dasharray(percent)
    "#{(RING_CIRCUMFERENCE * percent / 100.0).round(1)} #{RING_CIRCUMFERENCE}"
  end

  def kg(value)
    number_with_precision(value, precision: 1, strip_insignificant_zeros: false)
  end

  def workout_status_label(workout)
    { "planned" => "Not started", "done" => "Done", "skipped" => "Skipped" }.fetch(workout.status, workout.status.to_s.capitalize)
  end
end
