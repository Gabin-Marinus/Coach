class AddThemeToUsers < ActiveRecord::Migration[8.1]
  def change
    # "system" (follow the phone/computer setting), "light" or "dark"
    add_column :users, :theme, :string, default: "system", null: false
  end
end
