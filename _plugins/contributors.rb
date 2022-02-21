# frozen_string_literal: true

module Jekyll
  # Contributor pages collect editors and authors from a book
  class ContributorPage < Page
    attr_reader :layout, :permalink, :basename

    def initialize(site, book, contributors = [])
      @site = site
      @layout = 'contributor'
      @ext = '.html'
      @permalink = "#{book.url}contributors/"
      @basename = 'contributors'
      @data = {
        'title' => 'Contributors',
        'layout' => layout,
        'book' => book,
        'contributors' => contributors,
      }

      book.data['contributors'] = self
    end
  end

  # A collection of works cited
  class WorksCitedPage < Page
    attr_reader :layout, :permalink, :basename

    def initialize(site, document, book)
      @site = site
      @layout = 'works_cited'
      @ext = '.html'
      @permalink = "#{document.url}works_cited/"
      @basename = 'works_cited'
      @data = {
        'title' => 'Works Cited',
        'layout' => layout,
        'works_cited' => document.data['works_cited'] || [],
        'book' => book,
        document.data['layout'] => document
      }

      # XXX: This changes the relation to the page, so to access the
      # actual array of documents from a book, you'll need to use
      # {{ book.works_cited.works_cited }}
      document.data['works_cited'] = self
    end
  end

  # The search page
  class SearchPage < Page
    attr_reader :layout, :permalink, :basename

    def initialize(site)
      @site = site
      @layout = 'search'
      @ext = '.html'
      @permalink = "/search/"
      @basename = 'search'
      @data = {
        'title' => 'Search',
        'layout' => layout
      }

      site.config['search'] = self
    end
  end
end

# Creates pages collection content
Jekyll::Hooks.register :site, :post_read, priority: :low do |site|
  next if ENV.fetch('JEKYLL_ENV', '').include? 'migration'

  site.pages << Jekyll::SearchPage.new(site)

  site.documents.each do |doc|
    # Works cited don't polute the sitemap
    doc.data['sitemap'] = false if doc.data['layout'] == 'work_cited'

    next unless site.config['book_layouts'].include? doc.data['layout']

    book = doc

    contributors = []
    contributors << book.data['editors']
    contributors << book.data['extra_contributors']
    contributors << book.data['essays']&.map do |essay|
      essay.data['authors']
    end

    # All contributors are sorted alphabetically by last name
    contributors = contributors.flatten.compact.uniq.map do |c|
      Jekyll.logger.warn "#{c.relative_path} doesn't have a last_name field" unless c.data['last_name']
      Jekyll.logger.warn "#{c.relative_path} doesn't have a first_name field" unless c.data['first_name']

      c.data['sortable_name'] = Jekyll::Utils.slugify("#{c.data['last_name']} #{c.data['first_name']}", mode: 'latin')
      c
    end.sort do |a, b|
      a.data['sortable_name'] <=> b.data['sortable_name']
    end

    site.pages << Jekyll::ContributorPage.new(site, book, contributors)
    site.pages << Jekyll::WorksCitedPage.new(site, book, book)

    book.data['essays'].each do |essay|
      next if essay.data['works_cited'].nil? || essay.data['works_cited'].empty?

      site.pages << Jekyll::WorksCitedPage.new(site, essay, book)
    end
  end
end
