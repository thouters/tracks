require 'test_helper'
require 'support/html_entity_helper'

class ProjectsControllerTest < ActionController::TestCase
  include HTMLEntityHelper

  def setup
  end

  def test_board_puts_projects_in_columns
    users(:admin_user).prefs.update!(theme: 'modern')
    projects(:moremoney).hide!
    projects(:gardenclean).complete!
    login_as :admin_user
    get :board
    assert_response :success
    columns = assigns['board_columns']
    assert_equal Project::STAGES, columns.keys
    assert_includes columns['doing'], projects(:timemachine)
    assert_includes columns['idea'], projects(:moremoney)
    assert_includes columns['done'], projects(:gardenclean)
    assert_not_includes columns.values.flatten, projects(:attendrailsconf)
    assert_select '#mx-board .mx-column', 5
    assert_select '.mx-nav-link[href=?]', board_projects_path
  end

  def test_board_move_sets_stage_state_and_order
    login_as :admin_user
    a, b = projects(:timemachine), projects(:gardenclean)
    post :board_move, params: { id: a.id, stage: 'planned', order: [b.id, a.id] }, format: :json
    assert_response :success
    a.reload
    assert_equal 'planned', a.board_stage
    assert a.active?
    assert_equal 1, a.board_position
    assert_equal 0, b.reload.board_position

    post :board_move, params: { id: a.id, stage: 'idea', order: [a.id] }, format: :json
    assert a.reload.hidden?

    post :board_move, params: { id: a.id, stage: 'done', order: [] }, format: :json
    assert a.reload.completed?
    assert_equal 'done', a.board_stage

    post :board_move, params: { id: a.id, stage: 'waiting', order: [a.id] }, format: :json
    assert a.reload.active?
    assert_equal 'waiting', a.board_stage
  end

  def test_board_move_rejects_unknown_stage_and_other_users_projects
    login_as :admin_user
    post :board_move, params: { id: projects(:timemachine).id, stage: 'nonsense' }, format: :json
    assert_response :unprocessable_entity
    assert_raises(ActiveRecord::RecordNotFound) do
      post :board_move, params: { id: projects(:attendrailsconf).id, stage: 'doing' }, format: :json
    end
  end

  def test_board_create_adds_project_to_column
    login_as :admin_user
    assert_difference 'Project.count' do
      post :board_create, params: { name: 'Nieuw speeltje', stage: 'idea' }
    end
    project = Project.find_by(name: 'Nieuw speeltje')
    assert project.hidden?
    assert_equal 'idea', project.board_stage
    assert_redirected_to board_projects_path(anchor: 'mx-col-idea')
  end

  def test_projects_list
    login_as :admin_user
    get :index
  end

  def test_show_exposes_deferred_todos
    p = projects(:timemachine)
    login_as :admin_user
    get :show, params: { :id => p.to_param }
    assert_not_nil assigns['deferred_todos']
    assert_equal 1, assigns['deferred_todos'].size

    t = p.todos.not_completed[0]
    t.show_from = 1.days.from_now.utc
    t.save!

    get :show, params: { :id => p.to_param }
    assert_equal 2, assigns['deferred_todos'].size
  end

  def test_sorted_current_in_review
    p = projects(:timemachine)
    login_as :admin_user
    get :review
    current_projects = assigns['current_projects']
    assert_equal 2, current_projects.length
    assert_equal projects(:gardenclean), current_projects[0]
    assert_equal projects(:moremoney), current_projects[1]
  end

  def test_show_exposes_next_project_in_same_state
    login_as :admin_user
    get :show, params: { :id => projects(:timemachine).to_param }
    assert_equal(projects(:moremoney), assigns['next_project'])
  end

  def test_show_exposes_previous_project_in_same_state
    login_as :admin_user
    get :show, params: { :id => projects(:moremoney).to_param }
    assert_equal(projects(:timemachine), assigns['previous_project'])
  end

  def test_create_project_via_ajax_increments_number_of_projects
    login_as :other_user
    assert_ajax_create_increments_count 'My New Project'
  end

  def test_todo_is_hidden_after_hiding_project
    p = projects(:timemachine)
    todos = p.todos.active
    login_as(:admin_user)
    post :update, xhr: true, params: { :id => 1, "project"=>{"name"=>p.name, "description"=>p.description, "state"=>"hidden"} }
    todos.each do |t|
      assert t.reload().hidden?
    end
    assert p.reload().hidden?
  end

  def test_not_done_counts_after_hiding_and_unhiding_project
    p = projects(:timemachine)
    todos = p.todos.active
    login_as(:admin_user)
    post :update, xhr: true, params: { :id => 1, "project"=>{"name"=>p.name, "description"=>p.description, "state"=>"hidden"} }
    post :update, xhr: true, params: { :id => 1, "project"=>{"name"=>p.name, "description"=>p.description, "state"=>"active"} }
    todos.each do |t|
      assert_equal :active, t.reload().aasm.current_state
    end
    assert p.reload().active?
  end

  # RSS

  def test_rss_feed_content
    login_as(:admin_user)
    get :index, params: { :format => "rss" }
    assert_equal 'application/rss+xml', @response.media_type
    #puts @response.body

    assert_select 'rss[version="2.0"]' do
      assert_select 'channel' do
        assert_select '>title', 'Tracks Projects'
        assert_select '>description', "Lists all the projects for #{users(:admin_user).display_name}"
        assert_select 'language', 'en-us'
        assert_select 'ttl', '40'
      end
      assert_select 'item', 3 do
        assert_select 'title', /.+/
        assert_select 'description' do
          assert_select_encoded do
            assert_select 'p', /^\d+#{nbsp}actions\. Project is (active|hidden|completed)\.$/
          end
        end
        %w(guid link).each do |node|
          assert_select node, /http:\/\/test.host\/projects\/.+/
        end
        assert_select 'pubDate', projects(:timemachine).updated_at.to_s(:rfc822)
      end
    end
  end

  def test_rss_feed_not_accessible_to_anonymous_user_without_token
    login_as nil
    get :index, params: { :format => "rss" }
    assert_response 401
  end

  def test_rss_feed_not_accessible_to_anonymous_user_with_invalid_token
    login_as nil
    get :index, params: { :format => "rss", :token => 'foo'  }
    assert_response 401
  end

  def test_rss_feed_accessible_to_anonymous_user_with_valid_token
    login_as nil
    get :index, params: { :format => "rss", :token => users(:admin_user).token }
    assert_response :ok
  end

  def test_atom_feed_content
    login_as :admin_user
    get :index, params: { :format => "atom" }
    assert_equal 'application/atom+xml', @response.media_type
    assert_equal 'http://www.w3.org/2005/Atom', html_document.children[0].namespace.href
    assert_select 'feed' do
      assert_select '>title', 'Tracks Projects'
      assert_select '>subtitle', "Lists all the projects for #{users(:admin_user).display_name}"
      assert_select 'entry', 3 do
        assert_select 'title', /.+/
        assert_select 'content[type="html"]' do
          assert_select_encoded do
            assert_select 'p', /\d+#{nbsp}actions. Project is (active|hidden|completed)./
          end
        end
        assert_select 'published', /(#{Regexp.escape(projects(:timemachine).updated_at.xmlschema)}|#{Regexp.escape(projects(:moremoney).updated_at.xmlschema)})/
      end
    end
  end

  def test_atom_feed_not_accessible_to_anonymous_user_without_token
    login_as nil
    get :index, params: { :format => "atom" }
    assert_response 401
  end

  def test_atom_feed_not_accessible_to_anonymous_user_with_invalid_token
    login_as nil
    get :index, params: { :format => "atom", :token => 'foo'  }
    assert_response 401
  end

  def test_atom_feed_accessible_to_anonymous_user_with_valid_token
    login_as nil
    get :index, params: { :format => "atom", :token => users(:admin_user).token }
    assert_response :ok
  end

  def test_text_feed_content
    login_as :admin_user
    get :index, params: { :format => "txt" }
    assert_equal 'text/plain', @response.media_type
    assert !(/&nbsp;/.match(@response.body))
  end

  def test_text_feed_content_for_projects_with_no_actions
    login_as :admin_user
    p = projects(:timemachine)
    p.todos.each(&:destroy)

    get :index, params: { :format => "txt", :only_active_with_no_next_actions => true }
    assert (/^\s*BUILD A WORKING TIME MACHINE\s+0 actions. Project is active.\s*$/.match(@response.body))
    assert !(/[1-9] actions/.match(@response.body))
  end

  def test_text_feed_not_accessible_to_anonymous_user_without_token
    login_as nil
    get :index, params: { :format => "txt" }
    assert_response 401
  end

  def test_text_feed_not_accessible_to_anonymous_user_with_invalid_token
    login_as nil
    get :index, params: { :format => "txt", :token => 'foo'  }
    assert_response 401
  end

  def test_text_feed_accessible_to_anonymous_user_with_valid_token
    login_as nil
    get :index, params: { :format => "txt", :token => users(:admin_user).token }
    assert_response :ok
  end

  def test_actionize_sorts_active_projects_by_number_of_tasks
    login_as :admin_user
    u = users(:admin_user)
    post :actionize, params: { :state => "active", :format => 'js' }

    assert_equal 1, projects(:gardenclean).position
    assert_equal 2, projects(:moremoney).position
    assert_equal 3, projects(:timemachine).position
  end

  def test_alphabetize_sorts_active_projects_alphabetically
    login_as :admin_user
    u = users(:admin_user)
    post :alphabetize, params: { :state => "active", :format => 'js' }
    assert_equal 1, projects(:timemachine).position
    assert_equal 2, projects(:gardenclean).position
    assert_equal 3, projects(:moremoney).position
  end

  def test_alphabetize_assigns_state
    login_as :admin_user
    post :alphabetize, params: { :state => "active", :format => 'js' }
    assert_equal "active", assigns['state']
  end

  def test_alphabetize_assigns_projects
    login_as :admin_user
    post :alphabetize, params: { :state => "active", :format => 'js' }
    exposed_projects = assigns['projects']
    assert_equal 3, exposed_projects.length
    assert_equal projects(:timemachine), exposed_projects[0]
    assert_equal projects(:gardenclean), exposed_projects[1]
    assert_equal projects(:moremoney), exposed_projects[2]
  end

  # XML (REST API)

  def test_xml_content
    login_as(:admin_user)
    get :index, params: { :format => "xml" }
    assert_equal 'application/xml', @response.media_type

    assert_select 'projects' do
      assert_select 'project', 3 do
        assert_select 'name', /.+/
        assert_select 'state', 'active'
      end
    end
  end

  def test_xml_not_accessible_to_anonymous_user_without_token
    login_as nil
    get :index, params: { :format => "xml" }
    assert_response 401
  end

  def test_xml_not_accessible_to_anonymous_user_with_invalid_token
    login_as nil
    get :index, params: { :format => "xml", :token => 'foo'  }
    assert_response 401
  end

  def test_xml_accessible_to_anonymous_user_with_valid_token
    login_as nil
    get :index, params: { :format => "xml", :token => users(:admin_user).token }
    assert_response :ok
  end

end
