class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_workspace, :current_user

  private

  # v1 portfolio demo runs without auth — there's exactly one workspace and
  # one user. Replace with session-backed lookups if multi-tenant auth is
  # added.
  def current_workspace
    @current_workspace ||= Workspace.first!
  end

  def current_user
    @current_user ||= User.first!
  end
end
