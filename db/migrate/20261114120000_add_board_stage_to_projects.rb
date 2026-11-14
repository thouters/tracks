# The project board (projects#board): the column a project is in and its
# place in that column, i.e. its priority
class AddBoardStageToProjects < ActiveRecord::Migration[6.1]
  def change
    add_column :projects, :stage, :string, limit: 20
    add_column :projects, :board_position, :integer
  end
end
