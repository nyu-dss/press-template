# Draft schema

Definition for the different types of posts and an approximate migration
to Jekyll.

Using African American Studies (Blog ID 13) as base.  (Note: Tried with
Comics, ID 13, but the side drawer opens and closes automatically and
I can't browse it.)

Post types:

```
attachment
essay
nav_menu_item
page
post
revision
works_cited
```

Posts don't seem to have extra metadata attached, their `terms` and
`postmeta` tables are empty or contain data related to the navigation.

## Post types

### `post`

Not in use.

### `revision`

Used internally by WP to store previous versions.

### `page`

They can have a template of `default` or `page-authored`, the only
change is that one has space for authorship.  I would convert this into
an optional field.

Authors are linked from `wp_users` table joining it with
`wp_13_postmeta` by `meta_key` of value `"nyukeywords_multiauthor"`.

They can belong to another page and when they do, their slugs are
concatenated, so
"https://keywords.nyupress.org/latina-latino-studies/in-the-classroom/syllabi-and-assignments/introduction-to-latina-o-studies-university-of-michigan-ann-arbor-lawrence-la-fountain-stokes/"
is formed.

Since the Syllabi and Classroom articles are "parents" of the
assignments but they need to be created beforehand and don't have
a content of their own, I'm inclined to generate this pages
automatically in some way.

Same por the Home.

### `essay`

Authors are linked from `wp_users` table joining it with
`wp_13_postmeta` by `meta_key` of value `"nyukeywords_multiauthor"`.

Availability is linked from `wp_13_terms` via
`wp_13_term_relationships`.

Book is the multisite blog they belong to.

* `guid` is the URI, but it's not the same as the public URL
* `post_name` is the keyword in lower case and acts as a slug
* `post_title` is the title
* `post_content` is the content in HTML.  Citations are links to posts
of type `works_cited` with full public URL.

