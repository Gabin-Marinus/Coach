module ApplicationHelper
  STATUS_BADGES = { "planned" => "secondary", "done" => "success", "skipped" => "warning" }.freeze

  def render_markdown(text)
    Kramdown::Document.new(text, input: "GFM", syntax_highlighter: "rouge").to_html
  end

  def status_badge(status)
    content_tag(:span, status.to_s.capitalize, class: "badge text-bg-#{STATUS_BADGES.fetch(status, 'secondary')}")
  end
end
