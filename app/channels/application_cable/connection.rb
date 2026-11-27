module ApplicationCable
  # Live updates (the coach's answer appearing bit by bit) are only for logged-in users
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = env["warden"].user || reject_unauthorized_connection
    end
  end
end
