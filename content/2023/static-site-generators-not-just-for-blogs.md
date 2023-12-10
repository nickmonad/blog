+++
title = "Static Site Generators: Not Just for Blogs"
description = "Static generation should be the default"
draft = true
date = 2023-12-11
[taxonomies]
tags = [ "web" ]
+++

Static site generators have become popular within the technical and programming focused communities. They are fast, focused
programs that allow anybody with a little bit of HTML and CSS skill to produce a blog or product page quickly, write all their
content (typically) using [markdown](https://en.wikipedia.org/wiki/Markdown) in a simple folder structure, and commit it
all to git. Truly a gift and a joy to work with, compared to something like Wordpress.

[Cloudflare](https://www.cloudflare.com/learning/performance/static-site-generator/) defines a
static site generator (SSG) as **"a tool that generates a full static HTML website based on raw data and a set of templates"**.
In this context, "static" means that the end result of the build is a set of HTML pages that don't change when the page is
refreshed, not that those pages _never_ change.

Static site generators are incredibly powerful tools available for modern web development and I think a lot of developers
are missing out on what they offer in terms of development time, hosting cost, and overall simplicity.

## Blog Bias

Blogs are common examples that come up when researching static site generators and how they can be used. This
makes a lot of sense, as once blog posts are published, they rarely change, and they need to load quickly. In the context
of a company blog, SEO is a major factor as well, since search engine crawlers need to parse content quickly.

Unfortunately, I think a lot of the understanding around static site generation ends here, even among web developers.
For a long time, I was in this camp as well. I knew I could use static site generation effectively for my blog site, or
a simple "about" page here or there, and maybe even a legal statement or privacy policy. Basically, anything where
the content could be shown in a long, continuous block of text.

This understanding makes some product pages, or pages that require laying out collections of blocks in a grid-like
structure difficult to reason about, and nearly impossible to build in some cases. If I can only store content in a big
blob of text, and each document in my repository is a single page, how would I break it up so I can spread out the
content to different sections of the page and style it appropriately? Worse yet, how would the non-technical team members
update copy on the page without having to dig around in the HTML directly?

## Options for managing structured content

I'm going to use [zola](https://www.getzola.org/) as my static site generator of choice and show some examples of
creating and rendering "non-blog" content, in a few different ways. This is only because I'm the most familiar with it,
but there are lots of good options out there, such as [hugo](https://gohugo.io/). They may or may not work in exactly
the same way, but what's important here is taking the ideas and expanding our understanding of how we can utilize SSGs
to their full potential.

### 1. Section and Page Metadata

Sometimes called "front matter", each section or page of our site can have metadata associated with it.

Even in the case of a blog, you'll see this metadata above the markdown content, enclosed in some kind of marker, to
separate it from the main content of the post. This would include things like `title`, `description`, `author`, and `date`,
and read by the static site generator itself to organize and template the page. The front matter of this post looks like,

```
+++
title = "Static Site Generators: Not Just for Blogs"
description = "Static generation should be the default"
date = 2023-12-11
[taxonomies]
tags = [ "web" ]
+++
```

The easiest way to add structured data to this page would be to use the built-in `[extra]` field for our custom content.

```
+++
...

[extra]
seo_keywords = "please, read, my, blog"
+++
```

Then, inside of the template that renders the page, we can include these keywords in our block that allows for `<meta>`
tag keywords to be added,

```html
{% extends "base.html" %}

{% block title %}{{ page.title }}{% endblock %}
{% block seo_keywords %}{{ page.extra.seo_keywords }}{% endblock %}
```

which could generate HTML that looks like this,

```html
# template
<meta name="keywords" content="{% block seo_keywords %}{% endblock seo_keywords %}">

# rendered
<meta name="keywords" content="please, read, my, blog">
```

To build upon this example, imagine instead we had a product page and we wanted to specify a list of features.

```
+++
...

[extra]

[[extra.features]]
headline = "Amazing Feature"
description = "Do something amazing."

[[extrea.features]]
headline = "Awesome Feature"
description = "Do something awesome, instead."
+++
```

Here, we have separated the content of each feature item from the display and styling of them. In our template,
we can now iterate over each of these feature items and place them however we want on the page, using the `page.extra.features`
array.

### 2. Data in templates

In many cases, it's useful to store website copy (especially marketing copy) in a content management system (CMS),
where non-technical team members can edit and review content before it goes live on the website.

The section and page metadata approach falls a bit short, since it still requires modifying files locally and committing
them to git.

Fortunately, `zola` offers a [`load_data`](https://www.getzola.org/documentation/templates/overview/#load-data) function
to bring in data from a remote source, within a template.

As an example, we can build up a SaaS pricing page this way, using an endpoint in our hypothetical CMS.

```
{% set token = get_env(name="API_TOKEN") %}
{% set data = load_data(url="https://my.cms.com/api/data/pricing", format="json", headers=["Accept=application/json", "Authorization=Bearer " ~ token]) %}

<h1>{{ data.tiers[0].name }}</h1>
<ul>
{% for feature in data.tiers[0].features %}
    <li>{{ feature }}</li>
{% endfor %}
</ul>
```

> The "url" passed to `load_data` can be a local file as well, if it makes sense to store that JSON locally.

This gives us the flexibility to put content somewhere else that is more accessible to a wider group of people on our team.
Any change in the CMS can be detected (hopefully via a webhook) and the site can be rebuilt, previewed and pushed to production.

> **Side note**: static site generators are _fast_. This entire site builds in just under 100ms.

### 3. Automated markdown file generation

Finally, there is always the option to generate a set of markdown files to be placed in the `content` directory. This is the
approach I've taken for the [bips.dev](https://bips.dev) site, where each BIP is a separate page, with front matter and markdown
generated from a script that uses [`pandoc`](https://pandoc.org/) to translate the media wiki format to markdown.

Admittingly, it's a bit of a hack, but it does work. Large documentation sites could be built this way with content from a
CMS. This method would be needed whenever the actual structure of the site is dictated by some other source. In the case
of `bips.dev`, that source is a [public git repository](https://github.com/bitcoin/bips).

## Simple as the default

**TL;DR**

With the proliferation and increasing sophistication of SSGs, I think the time has come where we can say that the _default_
choice of any "non-application" website should be static generation. Statically generated sites are faster to develop,
easier to host, and easier to reason about over the lifetime of the project.

I want to be explicit in stating what I hope is the obvious: If you are building a highly interactive application with
lots of business logic, _obviously_ a fully featured programming language and deployment environment is going to be a better option.
I think that statically generated sites still offer some room to include interaction and business logic with client-side
Javascript ([alpine.js](https://alpinejs.dev/) is a great candidate here), and that can always be included as part of
your templates and build output.

I would even go so far as to say that needing to have a few business logic endpoints shouldn't completely eliminate the
possibility of using a static site generator, as you could simply have a reverse proxy forward those requests to an
application server, and just serve the static content for everything else. Some judgement would need to be exercised there,
to see if it makes sense for the use-case, but I would still take a moment to see if that model could satisfy your requirements.

On the infrastructure side, hosting a statically generated site is just about the easiest thing to do.
From a self-hosted `nginx` instance to a managed platform that watches for changes in your git repo and builds the latest
version of the site with automatic certificate renewal, there are tons of reliable options.

A recent website rebuild I worked on spent far more time than necessary dealing with the heavy frontend framework that was
chosen, mainly because the full scope of how static site generators could be used wasn't known at the time.

It's tempting to reach for those languages and tools, since they are familiar to a lot of developers. At some point though,
we have to use the best tool for the job, and bringing along all of React to build out a few product pages just doesn't seem like
the way to go.

I could be way behind on this. If you're reading and find all it to be blatantly obvious, or something that was figured out
years ago, awesome! In my recent experience, there is still a lack of understanding around SSGs, and I hope we'll see a renaissance
soon, where the simple choice is the default choice.
