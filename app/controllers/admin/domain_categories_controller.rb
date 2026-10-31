module Admin
  # POST /admin/domain_categories: fix a domain's category by hand. Manual
  # rows always win: the AI never overwrites an existing row.
  class DomainCategoriesController < BaseController
    before_action :verify_form_token

    def create
      row = DomainCategory.find_or_initialize_by(domain: DomainCategory.normalize_domain(params[:domain]))
      row.assign_attributes(category: params[:category], source: "manual", confidence: nil)

      if row.save
        redirect_to admin_root_path(saved: row.domain) # no session here, so no flash
      else
        render plain: row.errors.full_messages.to_sentence, status: :unprocessable_entity
      end
    end
  end
end
