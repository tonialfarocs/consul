module Budgets
  class InvestmentsController < ApplicationController
    include FeatureFlags
    include CommentableActions
    include FlagActions

    before_action :authenticate_user!, except: [:index, :show]

    load_and_authorize_resource :budget

    load_and_authorize_resource :investment, through: :budget, class: "Budget::Investment"
    before_action -> { flash.now[:notice] = flash[:notice].html_safe if flash[:html_safe] && flash[:notice] }
    before_action :load_ballot, only: [:index, :show]
    before_action :load_heading, only: [:index, :show]
    before_action :set_random_seed, only: :index
    before_action :load_categories, only: [:index, :new, :create]
    before_action :set_default_budget_filter, only: :index

    feature_flag :budgets

    has_orders %w{most_voted newest oldest}, only: :show
    has_orders ->(c) { c.instance_variable_get(:@budget).investments_orders }, only: :index
    has_filters %w{not_unfeasible feasible unfeasible unselected selected selected_by_assembly unselected_by_assembly}, only: [:index, :show, :suggest]

    invisible_captcha only: [:create, :update], honeypot: :subtitle, scope: :budget_investment

    helper_method :resource_model, :resource_name
    respond_to :html, :js

    def index
      @investments = investments.page(params[:page]).per(10).for_render
      @investment_ids = @investments.pluck(:id)
      load_investment_votes(@investments)
      @tag_cloud = tag_cloud
    end

    def new
    end

    def show
      @commentable = @investment
      @comment_tree = CommentTree.new(@commentable, params[:page], @current_order)
      @related_contents = Kaminari.paginate_array(@investment.relationed_contents).page(params[:page]).per(5)
      set_comment_flags(@comment_tree.comments)
      load_investment_votes(@investment)
      @investment_ids = [@investment.id]
    end

    def create
      @investment.author = current_user
      if @investment.save
        Mailer.budget_investment_created(@investment).deliver_later
        redirect_to budget_investment_path(@budget, @investment),
                    notice: t('flash.actions.create.budget_investment')
      else
        render :new
      end
    end

    def destroy
      @investment.destroy
      redirect_to user_path(current_user, filter: 'budget_investments'), notice: t('flash.actions.destroy.budget_investment')
    end

    def vote
      @investment.register_selection(current_user)
      load_investment_votes(@investment)
      respond_to do |format|
        format.html { redirect_to budget_investments_path(heading_id: @investment.heading.id) }
        format.js
      end
    end

    def suggest
      @resource_path_method = :namespaced_budget_investment_path
      @resource_relation    = resource_model.where(budget: @budget).apply_filters_and_search(@budget, params, @current_filter)
      super
    end

    private

    def resource_model
      Budget::Investment
    end

    def resource_name
      "budget_investment"
    end

    def load_investment_votes(investments)
      @investment_votes = current_user ? current_user.budget_investment_votes(investments) : {}
    end

    def set_random_seed
      if params[:order] == 'random' || params[:order].blank?
        seed = rand(-100..100) / 100.0
        params[:random_seed] ||= Float(seed) rescue 0
      else
        params[:random_seed] = nil
      end
    end

    def investment_params
      params[:budget_investment][:tag_list] = locate(params[:budget_investment][:tag_list])
      params[:budget_investment][:tag_list] = add_organization(params[:budget_investment][:tag_list])
      params.require(:budget_investment)
            .permit(:title, :description, :heading_id, :tag_list,
                    :organization_name, :location, :terms_of_service, :skip_map,
                    image_attributes: [:id, :title, :attachment, :cached_attachment, :user_id, :_destroy],
                    documents_attributes: [:id, :title, :attachment, :cached_attachment, :user_id, :_destroy],
                    map_location_attributes: [:latitude, :longitude, :zoom])
    end

    def load_ballot
      query = Budget::Ballot.where(user: current_user, budget: @budget)
      @ballot = @budget.balloting? ? query.first_or_create : query.first_or_initialize
    end

    def load_heading
      if params[:heading_id].present?
        @heading = @budget.headings.find(params[:heading_id])
        @assigned_heading = @ballot.try(:heading_for_group, @heading.try(:group))
      else
        @heading = nil #@budget.headings.last
        @assigned_heading = @ballot.try(:heading_for_group, @budget.headings.last.try(:group))
      end
    end

    def load_categories
      @categories = ActsAsTaggableOn::Tag.category.order(:name)
    end

    def tag_cloud
      TagCloud.new(Budget::Investment, params[:search])
    end

    def locate(tag_string)
      array_tags = tag_string.split(',').collect(&:strip).select(&:present?)
      array_tags.collect! { |t| I18n.translate(t, locale: :es, default: t)}
      array_tags.join(',')
    end

    def add_organization(tag_string)
      return tag_string unless params[:budget_investment][:organization_name].present?
      array_tags = tag_string.split(',').collect(&:strip)
      array_tags << 'Asociaciones' unless array_tags.include?('Asociaciones')
      array_tags.join(',')
    end

    def investments
      if @current_order == 'random'
        @investments.apply_filters_and_search(@budget, params, @current_filter)
                    .send("sort_by_#{@current_order}", params[:random_seed])
      else
        @investments.apply_filters_and_search(@budget, params, @current_filter)
                    .send("sort_by_#{@current_order}")
      end
    end


  end

end
