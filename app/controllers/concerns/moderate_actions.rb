module ModerateActions
  extend ActiveSupport::Concern
  include Polymorphic

  def index
    @resources = @resources.send(@current_filter)
                           .send("sort_by_#{@current_order}")
                           .page(params[:page])
                           .per(50)
    set_resources_instance
  end

  def hide
    hide_resource resource
  end

  def moderate
    set_resource_params
    @resources = @resources.where(id: params[:resource_ids])

    if params['mark_unfeasible'].present?
      @resources.accessible_by(current_ability, :valuate).each {|resource| mark_unfeasible_resource resource}
    else
      if params[:hide_resources].present?
        a = @resources.accessible_by(current_ability, :hide)
        a.each {|resource| hide_resource resource}

      elsif params[:ignore_flags].present?
        @resources.accessible_by(current_ability, :ignore_flag).each(&:ignore_flag)

      elsif params[:block_authors].present?
        author_ids = @resources.pluck(author_id).uniq
        User.where(id: author_ids).accessible_by(current_ability, :block).each {|user| block_user user}
      end
    end

    redirect_to request.query_parameters.merge(action: :index)
  end

  private

    def load_resources
      @resources = resource_model.accessible_by(current_ability, :moderate)
    end

    def hide_resource(resource)
      if resource.respond_to?(:moderation_text)
        resource.moderation_text =  params[:moderation_texts][resource.id.to_s][:moderation_text]
        resource.aviso_moderacion
        resource.save
      end
      resource.hide
      Activity.log(current_user, :hide, resource)
    end

    def mark_unfeasible_resource(resource)
      # if resource.respond_to?(:moderation_text)
        resource.unfeasibility_explanation =  params[:moderation_texts][resource.id.to_s][:moderation_text]
        resource.feasibility = 'unfeasible'
        resource.valuation_finished = true
        resource.save
        resource.aviso_inviable
      # end
      Activity.log(current_user, :hide, resource)
    end

    def block_user(user)
      user.block
      Activity.log(current_user, :block, user)
    end

    def set_resource_params
      params[:resource_ids] = params["#{resource_name.gsub('::', '_')}_ids"]
      params[:hide_resources] = params["hide_#{resource_name.pluralize.gsub('::', '_')}"]
      params[:moderation_texts] = params["#{resource_name.gsub('::', '_')}"]
    end

    def author_id
      :author_id
    end

end
