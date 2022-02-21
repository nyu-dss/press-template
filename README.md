Data/Content repository for [Keywords](https://keywords.nyupress.org/)
migration.

# Adding a new book

[Read the documentation](_docs/adding_a_new_book.md)

# Posts

Posts have a single type ("layout" in Jekyll jargon), with certain
metadata defined by their schema.

Posts have a unique identifier using UUIDv4
(ie. `115d1e8f-4944-495b-8d63-a2bf96f828aa`).  They are randomly
generated and allow to identify posts regardless of content or metadata.

Posts can be interlinked by their UUIDs, in one-to-many --a book
contains many pages and a page belongs to a book--, and many-to-many
relationships --a work cited is used in many essays and an essay has
many works cited.

Posts are stored as files on the `_posts/` folder.  Files are named in
the format `yyyy-mm-dd-lower-case-titles-without-spaces.markdown`
(ie. `_posts/2021-01-01-african-american-studies.markdown`).  The
hyphenated title in lowercase is called a "slug" and is part of the
final URL.  Since posts are files, their names must be unique by the
combination of date and slug.  But this doesn't uniquely identify
a post, because dates and titles can change, so we use UUIDs internally.

# Schemas

![Diagram of post types, fields and relationships](site.png)

Each post type is defined by a schema, listing their fields, with their
types and requirements.

Available schemas are documented on the `_schemas/` folder.  They are
not written in a particular CMS format, because each CMS has its own.

* Book (`_schema/book.yml`): represents a single book and their information.

* Essay (`_schema/essay.yml`): individual essays linked to a book.

* Page (`_schema/page.yml`): individual pages linked to a book.  They
  can have different roles.

* Person (`_schema/person.yml`): a single person, who can be an author
  or a contributor, depending on where they're linked.

* Work cited (`_schema/work_cited.yml`): a citation reference that can
  be linked to essays.

* Menu item (`_schema/menu_item.yml`): the menu is created
  automatically, but this schema allows to create ad-hoc items.

# Automatic pages

Some pages and sections can be automatically created by Jekyll by using
plugins:

## Menus

Each book contains the required fields so the menu is automatically
created and ad-hoc items can be added as needed, so they won't need
manual interaction for most books.

## Contributors page

Since a list of contributors can be linked to a book, it's possible to
automatically generate this page by listing contributors names and bios.

## Works cited

By linking works cited to essays, it's possible to create:

* A page for the single work cited
* A page for works cited by an essay
* A page for works cited on the whole book

# Types

Each field (also called attribute, metadata, etc.) for a post has
a type.  This ensures the same field in a post contains the same type of
data, preventing bugs.

Field types are documented on the file `_schemas/types.yml`.

Jekyll stores fields and their values on a section of the Post file
called the "front matter" in [YAML](https://yaml.info/) format.  Some
fields like the content are placed outside this front matter, after the
second line of triple dashes.

Missing fields are considered empty and can enable or disable behavior
on the final site using conditional logic.  The CMS can require fields
to ensure there's no information missing, or even add default
information.

Example post: `_posts/2018-10-28-african-american-studies.markdown`

_______

**Note**: As of 2021-09-30, Issue in the repo have been migrated to: https://jira.nyu.edu/projects/KEYWORDS/. That Jira project is now used for issue tracking.
