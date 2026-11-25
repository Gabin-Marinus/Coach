class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
  before_action :authenticate_user! # added by Priscila

  def after_sign_in_path_for(resource)
    resource.profile_complete? ? root_path : edit_profile_path
  end

  def after_sign_in_path_for(resource)
    plan = resource.current_plan

    if plan&.ended?
      flash[:alert] = "Your plan ended on #{plan.end_date.strftime('%B %-d, %Y')}. " \
                      "Please review your profile and create a new plan."
      profile_path
    else
      super
    end
  end
end
