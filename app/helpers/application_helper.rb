module ApplicationHelper
  STATUS_BADGES = { "planned" => "secondary", "done" => "success", "skipped" => "warning" }.freeze

  def render_markdown(text)
    Kramdown::Document.new(text, input: "GFM", syntax_highlighter: "rouge").to_html
  end

  # Text inside an .ics file: commas, semicolons and line breaks need a "\" before them.
  # html_safe: it's not HTML, so Rails must not turn "&" into "&amp;"
  def ics_text(text)
    text.to_s.gsub(/[\\,;]/) { |char| "\\#{char}" }.gsub("\n", "\\n").html_safe
  end

  # Date in an .ics file: 2026-11-24 => "20261124"
  def ics_date(date)
    date.strftime("%Y%m%d")
  end

  def status_badge(status)
    content_tag(:span, status.to_s.capitalize, class: "badge text-bg-#{STATUS_BADGES.fetch(status, 'secondary')}")
  end
end
