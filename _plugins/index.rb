# frozen_string_literal: true

# After indexing, reopen the data file and remove the content for
# print-only essays, replacing it by their excerpt.
#
# Excerpts are the first paragraph on the post, so no content is leaked
# in the search index.
Jekyll::Hooks.register :site, :pre_render, priority: :low do |site|
  DATA_PATH = './data.json'

  next unless File.exist? DATA_PATH

  data = JSON.parse(File.read(DATA_PATH))
  documents = site.documents

  data.each do |doc|
    next unless doc['availability'] == site.config['default_availability']

    doc['content'] = documents.find do |d|
      doc['url'] == d.url
    end&.data&.dig('excerpt')&.content
  end

  FileUtils.rm DATA_PATH
  File.open(DATA_PATH, 'w') do |f|
    f.write JSON.dump(data)
  end
end
