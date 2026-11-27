module ApplicationHelper
  # "system", "light" or "dark": the user's choice; before logging in, the device decides
  def current_theme
    user_signed_in? ? current_user.theme : "system"
  end

  # The light and/or dark stylesheet. "system" loads both, and the browser uses the one that matches
  # the device's setting (media query), so the page never flashes in the wrong design.
  def theme_stylesheets
    case current_theme
    when "dark" then stylesheet_link_tag("application_dark", "data-turbo-track": "reload")
    when "light" then stylesheet_link_tag("application", "data-turbo-track": "reload")
    else
      safe_join([stylesheet_link_tag("application", media: "(prefers-color-scheme: light)", "data-turbo-track": "reload"),
                 stylesheet_link_tag("application_dark", media: "(prefers-color-scheme: dark)", "data-turbo-track": "reload")])
    end
  end
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
