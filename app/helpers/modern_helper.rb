# Helpers for the "modern" theme's layout (layouts/_modern_body): a sidebar
# with navigation, projects and contexts, a page header with a quick-add bar
# and filters, and a tab bar on phones.
module ModernHelper
  def modern_theme?
    @user_theme == 'modern'
  end

  # The page's title without the "TRACKS::" prefix most controllers give it
  def modern_page_title
    if controller_name == 'todos' && action_name == 'index'
      t('modern.next_actions')
    elsif controller_name == 'todos' && %w[done all_done].include?(action_name) && @page_title.blank?
      t('layouts.navigation.completed_tasks')
    else
      (@page_title || 'Tracks').to_s.sub(/\ATRACKS::\s*/i, '')
    end
  end

  # Whether this link points at the page being shown
  def modern_current?(path)
    current_page?(path)
  rescue StandardError
    false
  end

  def modern_nav_link(label, path, icon_name, count: nil, **options)
    classes = ['mx-nav-link']
    classes << 'is-current' if modern_current?(path)
    link_to(path, class: classes.join(' '), title: options[:title], accesskey: options[:accesskey]) do
      safe_join([
        icon('fas', icon_name, class: 'fa-fw mx-nav-icon'),
        content_tag(:span, label, class: 'mx-nav-label'),
        (count.to_i > 0 ? content_tag(:span, count, class: 'mx-nav-count') : nil)
      ].compact)
    end
  end

  # Active projects with their number of open actions and how far along they
  # are (completed / all), for the sidebar
  def modern_sidebar_projects
    @modern_sidebar_projects ||= begin
      projects = current_user.projects.active.order(:position).to_a
      open = current_user.todos.not_completed.where(project_id: projects.map(&:id)).group(:project_id).count
      done = current_user.todos.completed.where(project_id: projects.map(&:id)).group(:project_id).count
      projects.map do |project|
        o = open[project.id].to_i
        d = done[project.id].to_i
        { project: project, open: o, percent: (o + d).zero? ? 0 : (100 * d / (o + d)) }
      end
    end
  end

  # Active contexts with their number of actions to do now
  def modern_sidebar_contexts
    @modern_sidebar_contexts ||= begin
      contexts = current_user.contexts.active.order(:position).to_a
      counts = current_user.todos.active.where(context_id: contexts.map(&:id)).group(:context_id).count
      contexts.each_with_index.map do |context, i|
        { context: context, count: counts[context.id].to_i, color: (i % 4) + 1 }
      end
    end
  end

  def modern_next_actions_count
    @modern_next_actions_count ||= current_user.todos.active.not_hidden.count
  end

  def modern_tickler_count
    @modern_tickler_count ||= current_user.todos.deferred.count
  end

  def modern_starred_count
    @modern_starred_count ||= begin
      starred = Tag.where(name: 'starred', user_id: current_user.id).first
      starred ? current_user.todos.not_completed.with_tag(starred.id).count : 0
    end
  end
end
