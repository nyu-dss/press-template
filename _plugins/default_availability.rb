# frozen_string_literal: true

# If essays aren't categorized, default to least privilege access
Jekyll::Hooks.register :site, :post_read do |site|
  site.documents.each do |post|
    next unless post.data['layout'] == 'essay'

    post.data['availability'] ||= site.config['default_availability']
  end
end
