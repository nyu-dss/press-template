# frozen_string_literal: true

# This plugin finds the HTML versions for books and converts them into
# different layouts.  Books that are already migrated are ignored.
#
# Migrated content:
#
# * Book: A new post of layout book is added.
#
# * Essays: All essays are migrated.  Works cited need to be manually
# linked.
#
# * Contributors:  Individual person profiles are created or updated.
# Note this may update biographies on other books.  People with the same
# name would need to be disambiguated manually.
#
# * Works cited:  Individual citations are created.
#
# To migrate a book:
#
# * Create a folder under _html/ named as the book, in small caps and
# spaces converted to dashes, for instance, Comic Studies is
# _html/comic-studies/
#
# * Place the book HTML into this folder, named index.html:
# _html/comic-studies/index.html
#
# * Place the images folder inside the book folder:
# _html/comic-studiers/images/
#
# * Add everything to git, commit and push changes.  The build process
# will create the files and commit them to git.
#
# * Review and make changes.  The build history will give you hints on
# what couldn't be done automatically and needs your attention.

Jekyll::Hooks.register :site, :post_read do |site|
  next unless ENV['JEKYLL_ENV'] == 'html-migration'

  require 'jekyll-write-and-commit-changes'
  require 'sutty_migration/jekyll/document_creator'

  Jekyll::Document.include SuttyMigration::Jekyll::DocumentCreator

  # Ensure we can find documents
  unless Jekyll::Document.respond_to? :find_or_create
    Jekyll.logger.warn "The document creator plugin wasn't loaded correctly!"
    exit 1
  end

  require 'securerandom'
  require 'nokogiri'
  require 'reverse_markdown'

  LAYOUTS_WITH_BOOK = %w[essay page]
  # Usually it's Jr. but it doesn't hurt to support Junior as well
  JUNIOR_RE = /j(unio)?r\.?/i
  # Lastnames come after the last initial
  INITIALS_RE = /(?<firstnames>.*\.) (?<lastnames>.*)/
  # Process citations
  # slug: authors + year
  # authorship: anything non-numeric up to editors or year
  # editors: ed. or eds. also dir.
  # year: possible formats are:
  #   2000
  #   2000a
  #   2000-01 (and combinations of above)
  #   (2000) 2001 (and combinations of above)
  #   (2000, 2001) 2002 (and combinations of above)
  #   n.d
  #   n.d.-a
  #   forthcoming
  WORK_CITED_RE = /(?<slug>(?<authorship>[^0-9]+)(,? (eds?|dir))?[\.:]”?((,? ?\(?\d{4}([\-–0-9a-z]+)?\)?)+\.| ?n\.d\.(-[a-z]\.)?| ?forthcoming\.))/i
  SE_RE = /\.SE[0-9.]*/
  PUNCT_RE = /\s+(?<punct>[,\.:)!?])/
  DASHES_RE = /\A[-_—-]+([,.])/
  REMOVE_EDITORS_RE = /<h2[^>]*>\s*edited[^<]+<\/h2>/i
  READ_MORE_RE = /<a[^>]+>read[^<]+<\/a>/i
  LINKIFY_RE = %r{(?<url>https?://[^ ]+)}
  UNESCAPE_LINKS_RE = %r{<https?://[^>]+>}
  AUTHORSHIP_RE = %r{<(?<tag>strong|i|em|b)>(?<authorship>[^<]+)</\k<tag>>}
  NEWLINE_AFTER_TAG_RE = /(?<tag><[^>]+>)\n+/
  # Don't allow html tags with space or punctuation marks.
  EMPTY_HTML_RE = %r{<([^>]+)>([\s[:punct:]]*)</\1>}
  # Inline tags right next to each other
  UNNECESSARY_HTML_RE = %r{</(strong|em|i|b)>(\s*)<\1>}
  FIX_INLINE_TAGS_RE = %r{<i>(?<text1>[^<]+)?</strong>(?<text2>[^<]+)</i>}
  FIX_OPENING_TAG_BEFORE_PUNCT_RE = %r{(?<tag><\w+>)(?<punct>\.+)}
  QUOTES_RE = %r{["”]}
  # Sometimes posts can be duplicated, we deduplicate by prepending the
  # book slug to their file names
  DEDUPLICATE_LAYOUTS = %w[work_cited page essay]

  # Removes extra spaces and newlines
  string_sanitizer = lambda do |string|
    string.to_s.tr("\u2029", '').tr("\u00a0", ' ').tr("\n", ' ').squeeze(' ').strip
  end

  remove_empty_html = lambda do |html_string|
    html_string.gsub(EMPTY_HTML_RE, '\\2').gsub(UNESCAPE_LINKS_RE, '\\2')
  end

  # If there are inline tags with crossed boundaries, fix them
  fix_inline_tags = lambda do |html_string|
    html_string.gsub(FIX_INLINE_TAGS_RE, '\k<text1></strong> <i>\k<text2></i>')
  end

  # Tidies HTML
  tidy = lambda do |html_string|
    remove_empty_html.call(Nokogiri::HTML.fragment(fix_inline_tags.call html_string).to_s.gsub(NEWLINE_AFTER_TAG_RE, '\k<tag>')).gsub(FIX_OPENING_TAG_BEFORE_PUNCT_RE, '\k<punct> \k<tag>')
  end

  # Converts an HTML string into Markdown, removing unknown tags
  # (section, header) but keeping its contents.
  to_markdown = lambda do |html_string|
    ReverseMarkdown.convert(tidy.call(string_sanitizer.call(html_string.to_s)), unknown_tags: :bypass).gsub(PUNCT_RE, '\k<punct>')
  end

  as_set = lambda do |nil_array_or_set|
    case nil_array_or_set
    when NilClass then Set.new
    when Array then nil_array_or_set.to_set
    when Set then nil_array_or_set
    end
  end

  documents = site.documents
  years = {}
  people = documents.select do |doc|
    doc.data['layout'] == 'person'
  end.map do |person|
    [person.data['title'], person]
  end.to_h

  book_layout = [
    {
      title: 'Introduction',
      field: 'introduction',
      id: 'intro',
      layout: 'page',
      editors: true
    },
    {
      title: 'Acknowledgments',
      field: 'acknowledgments',
      id: 'acknow',
      layout: 'page'
    },
    {
      title: 'Appendix',
      id: 'app',
      layout: 'page'
    }
  ]

  # Remove values considered empty
  prune_data = lambda do |doc|
    doc.data.transform_values! do |value|
      case value
      when Set then value.to_a
      else value
      end
    end

    doc.data.reject! do |key, value|
      next true if key == 'save'

      case value
      when Array then value.empty?
      when Hash then value.empty?
      when Integer then false
      when FalseClass then true
      when NilClass then true
      when TrueClass then false
      when Jekyll::Excerpt then true
      when Jekyll::Document then false
      else value.blank?
      end
    end
  end

  # Create or update books in the _html/ directory.
  Dir.glob(File.join(site.source, '_html', '*')).each_with_index do |dir, i|
    unless File.directory? dir
      Jekyll.logger.warn "#{dir} is not a directory"
      next
    end

    index = File.join dir, 'index.html'
    book_slug = File.basename dir
    book_content_file = File.join dir, 'about.md'
    book_content = ''
    book_content = File.read(book_content_file) if File.exist? book_content_file

    unless File.exist? index
      Jekyll.logger.warn "#{index} is missing"
      next
    end

    html = Nokogiri::HTML File.read(index)
    # Find the publishing year
    year   = html.css('#cip').first&.text&.match(/© (?<year>\d{4})/)&.to_a&.last
    year ||= Time.now.year
    years[year] ||= [nil]
    years[year]  << book_slug

    # Finds or creates a document and sets initial front matter
    document_creator = lambda do |title, layout, slug = nil, book = nil|
      title  = string_sanitizer.call title
      slug ||= Jekyll::Utils.slugify(title, mode: 'latin')
      slug_is_empty = slug.blank?
      slug = Jekyll::Utils.slugify(title.bytes.join(' '), mode: 'latin') if slug_is_empty
      original_slug = slug
      slug = "#{book_slug}-#{slug}" if DEDUPLICATE_LAYOUTS.include? layout

      # XXX: The date is the publishing year plus an index for the book
      month = years[year].index(book_slug)
      Jekyll::Document.find_or_create(site: site, date: Time.new(year, month), title: title, slug: slug, collection: 'posts').tap do |d|
        d.data['layout'] = layout
        # Don't change the UUID
        d.data['uuid'] ||= SecureRandom.uuid
        d.data['slug'] ||= slug

        d.data['permalink'] ||= case layout
                                when 'book' then "/#{original_slug}/"
                                when 'person' then "/author/#{original_slug}/"
                                when 'essay' then "/#{book_slug}/essay/#{original_slug}/"
                                when 'work_cited' then "/#{book_slug}/works_cited/#{original_slug}/"
                                else "/#{book_slug}/#{original_slug}/"
                                end


        d.data['book'] = book if LAYOUTS_WITH_BOOK.include? layout

        Jekyll.logger.warn "Prevented empty post name for #{title} (#{d.relative_path}).  This could mean the title is empty or composed of non-alphabetic characters." if slug_is_empty
      end
    end

    # The HTML title includes the edition
    book_description   = html.xpath('/html/head/title').first&.text&.sub(/keywords for /i, '')
    book_description ||= book_slug.split('-').map(&:capitalize).join(' ')
    book_title = book_description.split(',', 2).first

    book = document_creator.call(book_title, 'book', book_slug).tap do |b|
      b.data['description'] = book_description
      b.content = book_content.split("\n", 2).first
    end

    # Extracts people names from a string and creates their documents if
    # they don't exist.  Keeps the order in which they were found.
    to_people = lambda do |people_string|
      string_sanitizer.call(people_string).sub(/,? (and|with) /, ',').split(',').map(&:strip).map do |person_name|
        people[person_name] ||= document_creator.call(person_name, 'person', nil, book)
        people[person_name].tap do |p|
          p.data['alternate-permalinks']  = as_set.call(p.data['alternate-permalinks']) << "#{book.data['permalink']}author/#{p.data['slug']}/"

          # Convert the simple cases for names
          # XXX: https://github.com/nyu-dss/keywords-data/issues/11
          name_parts = person_name.split(' ')

          # Junior is kept as part of lastname
          jr   = name_parts.pop if JUNIOR_RE =~ name_parts.last
          jr ||= nil

          # Firstname and Lastname are easiest to find
          # 
          # XXX: It could be possible that Eastern naming order is used,
          # but we don't have a way to know.
          #
          # @see {https://en.wikipedia.org/wiki/Surname#Order_of_names}
          if name_parts.size == 2
            p.data['first_name'], p.data['last_name'] = *name_parts
          # When names are initials, split last names from the last dot
          elsif name_parts.join.include? '.'
            _, p.data['first_name'], p.data['last_name'] = name_parts.join(' ').match(INITIALS_RE).to_a
          # Require human action
          elsif p.data['last_name'].nil?
            Jekyll.logger.warn "Couldn't detect first and last names for this person, please fix manually: #{person_name} (#{p.relative_path})"
            next
          end

          # Append Jr.
          p.data['last_name'] << " #{jr}" if jr
        end
      end.compact
    end

    Jekyll.logger.warn "Creating #{book.data['title']}, don't forget to add color to #{book.relative_path}"

    # Process an HTML section and create its document.
    section_to_document = lambda do |section, layout, book_field = nil, editors = false|
      title = section.css('h1:first-child')
      title.remove

      document_creator.call(title.text, layout, nil, book).tap do |d|
        # TODO: Get from schema, when we decide on CMS
        case book_field
        when 'essays' then book.data['essays'] = as_set.call(book.data['essays']) << d
        when 'pages' then book.data['pages'] = as_set.call(book.data['pages']) << d
        else book.data[book_field] = d
        end if book_field

        section_people = section.css('p.au')
        section_people.remove

        d.data['authors'] = to_people.call(section_people.text).map do |p|
          p.data['books']  = as_set.call(p.data['books']) << book
          p.data['posts']  = as_set.call(p.data['posts']) << d

          # Return this
          p
        end

        book.data['editors'] = d.data['authors'] if editors

        d.content = to_markdown.call section.inner_html.to_s
      end
    end

    # Pages
    book_layout.each do |layout|
      if (section = html.css("section[id=\"#{layout[:id]}\"]").first)
        document = section_to_document.call section, 'page', layout[:field], layout[:editors]
        prune_data.call document
        document.save
      else
        Jekyll.logger.warn "Couldn't find #{layout[:title]}"
      end
    end

    # Extra pages are identified by having a level 1 heading with class
    # ctfm.
    html.css('section:has(.ctfm)').each do |section|
      document = section_to_document.call section, 'page'
      prune_data.call document
      document.save
    end

    # Works cited
    works_cited = html.css('#refs').first
    works_cited ||= html.css('#biblio').first
    works_cited ||= html.css('#wrk_ctd').first

    if works_cited
      previous_authorship = nil
      # Keep size so we can store order.
      total_refs = 0

      works_cited.css('.rf,.rff').tap do |r|
        total_refs = r.size
      end.each_with_index do |ref, i|
        work_cited_title = string_sanitizer.call ref.text

        if work_cited_title.start_with?(DASHES_RE) && previous_authorship
          work_cited_title.sub!(DASHES_RE, "#{previous_authorship}\\1")
        end

        # Find authorship for citation format Authors. Year.
        _, slug, authorship = work_cited_title.match(WORK_CITED_RE).to_a
        # Remove extra editor role
        authorship&.sub! /,? eds?/, ''
        slug = Jekyll::Utils.slugify(slug, mode: 'latin')

        if slug.nil? || slug == work_cited_title
          Jekyll.logger.warn "Couldn't process work cited: #{work_cited_title}"
          next
        end

        work_cited = document_creator.call(work_cited_title, 'work_cited', slug, book).tap do |wc|
          wc.data['order'] = total_refs - i
          wc.data['authorship'] = authorship
          wc.data['book'] = book

          book.data['works_cited'] = as_set.call(book.data['works_cited']) << wc

          # Recover author and bold it
          wc.content = to_markdown.call(ref.inner_html.to_s).sub(DASHES_RE, "#{authorship}\\1").sub(/\A#{authorship}/, "**#{authorship}**")
        end

        prune_data.call work_cited
        work_cited.save
        previous_authorship = work_cited.data['authorship']
      end
    else
      Jekyll.logger.warn "Couldn't find Works cited"
    end

    # Essays.  They're identified by a section with a chapter number.
    html.css('section:has(.cn)').each do |essay_section|
      # Chapters start on odd pages
      page = essay_section.css('.page').first['id'].sub('p', '').to_i
      page = page + 1 if page % 2 == 0

      essay_section.css('.cn').remove

      document = section_to_document.call(essay_section, 'essay', 'essays').tap do |d|
        d.data['page'] = page
        # Essays are printed by default
        d.data['availability'] ||= site.config['default_availability']
      end

      prune_data.call document
      document.save
    end

    # Contributors.
    # XXX: Sometimes contributors are not correctly tagged, and it
    # depends on the book, there's no progression on the format.
    contributors   = html.css('#ab_contrib').first
    contributors ||= html.css('#contrib').first

    if contributors
      # XXX: Author bio has inconsistent naming.
      contributors.css('.aubio,.aubiof,.aubioft').each do |author|
        author_name = author.css('.aubion').first
        author_name&.name = 'strong'
        name = author_name&.text&.split(',', 2)&.first
        # Fallback.  Different ways in which author names can be split
        # from the text.
        name ||= author.text.split(/(( (is|holds|has)|,|’s) |—Research| \(@)/, 2).first
        name   = string_sanitizer.call(name)
        name.sub!(/dr\. /i, '')

        # At this point in the migration, all contributors' documents are
        # created.
        unless (person = people[name])
          # Fallback with fuzzy matching
          require 'jaro_winkler'

          match = people.map do |n, doc|
            [ JaroWinkler.distance(n, name, ignore_case: true), doc ]
          end.max do |a, b|
            a.first <=> b.first
          end

          if match.first > 0.9
            person = match.last

            Jekyll.logger.warn "Found similar name for #{name}: #{person.data['title']}"
          end
        end

        unless person
          Jekyll.logger.warn "Creating person profile who isn't linked to any page or essay: #{name}"

          adhoc_people = to_people.call(name)
          Jekyll.logger.warn "Creating a person profile created more than one person!" if adhoc_people.size > 1

          book.data['extra_contributors'] = as_set.call(book.data['extra_contributors']) << person = adhoc_people.first

          person.data['books'] = as_set.call(person.data['books']) << book
        end

        # XXX: On some books, the author name is bolden with <b> and it
        # goes up to the " is" part of the bio.
        person.content = to_markdown.call author.inner_html
        person.content.sub! /\A(.*#{name})/, "**\\1**" unless author_name
      end
    else
      Jekyll.logger.warn "Couldn't find Contributors section"
    end

    # Create an about page
    unless book.data['about']
      book.data['about'] = about = document_creator.call('About this Site', 'page', 'about-this-site', book).tap do |a|
        a.data['uuid'] = SecureRandom.uuid
        a.data['book'] = book
        a.data['authors'] = book.data['editors']
        a.data['authors'].each do |au|
          au.data['posts'] = as_set.call(au.data['posts']) << a
        end

        a.content = book_content
      end

      Jekyll.logger.warn "Created about page at #{about.relative_path}"

      prune_data.call about
      about.save
    end

    # Create a rights page
    unless book.data['rights']
      book.data['rights'] = rights = document_creator.call('Rights', 'page', 'rights-page', book).tap do |r|
        r.data['uuid'] = SecureRandom.uuid
        r.data['book'] = book
        r.content = <<~CONTENT
          _Keywords for #{book.data['title']}_ is © #{year} by New York
          University. Material on this website is licensed under a
          [Creative Commons Attribution-NonCommercial-NoDerivatives 4.0
          International
        License](http://creativecommons.org/licenses/by-nc-nd/4.0/).

          [![Creative Commons License](https://licensebuttons.net/l/by-nc-nd/4.0/88x31.png)](http://creativecommons.org/licenses/by-nc-nd/4.0/)
        CONTENT
      end

      Jekyll.logger.warn "Created rights page at #{rights.relative_path}"

      prune_data.call rights
      rights.save
    end

    prune_data.call book
    book.save
  end

  people.values.each do |person|
    prune_data.call person
    person.save
  end

  exit
end
